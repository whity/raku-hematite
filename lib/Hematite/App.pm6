use HTTP::Status;
use Cookie::Baker;
use JSON::Fast;
use Log;
use Hematite::Context;
use Hematite::Router;
use Hematite::Response;
use Hematite::Exceptions;
use Hematite::Templates;
use Hematite::Handler;

unit class Hematite::App is Hematite::Router;

has Callable %!render_handlers       = ();
has Callable %!error_handlers        = ();
has Hematite::Route %!routes_by_name = ();
has %.config                         = ();
has Log $.log;

method new(*%args) {
    return self.bless(|%args);
}

submethod BUILD(*%args) {
    %!config = %args;

    $!log = Log.new(level => %!config{'log_level'} || Log::INFO);

    # default handler
    self.error-handler('unexpected', sub ($ctx, *%args) {
        my $ex = %args{'exception'};
        my $status = 500;

        $ctx.response.set-code($status);
        $ctx.response.field(Content-Type => 'text/plain');
        $ctx.response.content =
            sprintf("%s\n%s", get_http_status_msg($status), $ex.gist);

        # log exception
        $ctx.log.error($ex.gist);

        return;
    });

    # halt default handler
    self.error-handler('halt', sub ($ctx, *%args) {
        my $status  = %args{"status"};
        my %headers = %(%args{"headers"});
        my $body = %args{"body"} || get_http_status_msg($status);

        my $res = $ctx.response;

        # set status code
        $res.set-code($status);

        # set headers
        $res.field(|%headers);

        # set content
        $res.content = $body;
    });

    # default render handlers

    self.render-handler('template', Hematite::Templates.new(|%args));
    self.render-handler('json', sub ($data, *%args) { return to-json($data); });

    return self;
}

multi method render-handler(Str $name) returns Callable {
    return %!render_handlers{$name};
}

multi method render-handler(Str $name, Callable $fn) {
    %!render_handlers{$name} = $fn;
    return self;
}

multi method error-handler(Str $name) returns Callable {
    return %!error_handlers{$name};
}

multi method error-handler(Str $name, Callable $fn) {
    %!error_handlers{$name} = $fn;
    return self;
}

multi method error-handler() {
    return self.error-handler('unexpected');
}

multi method error-handler(Int $status) {
    return self.error-handler(~($status));
}

multi method error-handler(Callable $fn) {
    return self.error-handler('unexpected', $fn);
}

multi method error-handler(Int $status, Callable $fn) {
    return self.error-handler(~($status), $fn);
}

method get-route(Str $name) {
    return %!routes_by_name{$name};
}

method handler() returns Callable {
    # prepare routes
    self.log.debug('preparing routes...');
    my @routes = self._prepare-routes;
    for @routes -> $route {
        if ($route.name) {
            %!routes_by_name{$route.name} = $route;
        }
    }

    # prepare main middleware
    self.log.debug('preparing middleware...');
    self.use(sub ($ctx) {
        for @routes -> $route {
            if ($route.match($ctx)) {
                $route($ctx);
                return;
            }
        }

        $ctx.not-found;
    });
    my $stack = self._prepare-middleware(self.middlewares);

    return Hematite::Handler.new(app => self, stack => $stack);
}

method _prepare-routes() returns Array {
    my @routes = self.routes;

    # sub-routers
    for self.groups.kv -> $pattern, $router {
        my @group_routes = $router._prepare-routes($pattern, []);
        @routes.append(@group_routes);
    }

    # sort routes
    @routes .= sort({ $^a.pattern cmp $^b.pattern });

    return @routes;
}
