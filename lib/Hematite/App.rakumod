use Hematite::Router;

unit class Hematite::App is Hematite::Router does Callable;

use HTTP::Status;
use JSON::Fast;
use Logger;
use Hematite::Context;
use Hematite::Response;
use Hematite::Templates;
use Hematite::Handler;
use X::Hematite;

my Lock $Lock = Lock.new;

has Callable %!render_handlers       = ();
has Callable %!exception_handlers    = ();
has Callable %!halt_handlers{Int}    = ();
has Hematite::Route %!routes_by_name = ();
has %.config                         = ();
has Logger $.log is rw;

has Hematite::Handler $!handler;

subset Helper where .signature ~~ :($ctx, |args);
has Helper %!helpers = ();

method new(*%args) {
    return self.bless(|%args);
}

submethod BUILD(*%args) {
    %!config = %args;

    # get the 'main' log that could be defined anywhere
    $!log = Logger.get;

    # error/exception default handler
    self.error-handler(sub ($ctx, *%args) {
        my Exception $ex = %args{'exception'};
        my $body         = sprintf("%s\n%s", get_http_status_msg(500), $ex.gist);

        $ctx.halt(
            status  => 500,
            body    => $body,
            headers => {
                'Content-Type' => 'text/plain',
            },
        );

        # log exception
        $ctx.log.error($ex.gist);

        return;
    });

    # halt default handler
    self.error-handler(X::Hematite::HaltException, sub ($ctx, *%args) {
        my Int $status = %args<status>;
        my %headers    = %args<headers>.Hash;
        my $body       = %args<body> || get_http_status_msg($status);

        my Hematite::Response $res = $ctx.response;

        my Bool $inline = $body.isa(Str) ?? True !! False;

        my %render_options = (
            inline => $inline,
            status => $status,
        );

        if (!(%args<body>:exists)) {
            %render_options<format> = 'text';
        }

        $ctx.render($body, |%render_options,);

        # set response headers
        $res.headers.clear();
        $res.headers.from-hash(%headers);

        return;
    });

    # default render handlers
    self.render-handler('template', Hematite::Templates.new(|(%args<templates> || %())));
    self.render-handler('json', sub ($data, *%args) {
        return (to-json($data), 'application/json');
    });

    self.startup if self.can('startup');

    return self;
}

method CALL-ME(Hash $env --> Array) {
    return self._handler.($env);
}

multi method render-handler(Str $name --> Callable) {
    return %!render_handlers{$name};
}

multi method render-handler(Str $name, Callable $fn) {
    %!render_handlers{$name} = $fn;
    return self;
}

multi method error-handler(Exception:U $type --> Callable) {
    return %!exception_handlers{$type.^name};
}

multi method error-handler(Exception:U $type, Callable $fn --> ::?CLASS) {
    %!exception_handlers{$type.^name} = $fn;
    return self;
}

multi method error-handler {
    return self.error-handler(Exception);
}

multi method error-handler(Callable $fn) {
    return self.error-handler(Exception, $fn);
}

multi method error-handler(Int $status --> Callable) {
    return %!halt_handlers{$status};
}

multi method error-handler(Int $status, Callable $fn --> ::?CLASS) {
    %!halt_handlers{$status} = $fn;
    return self;
}

method get-route(Str $name --> Hematite::Route) {
    return %!routes_by_name{$name};
}

multi method context-helper(Str $name, Helper $fn --> ::?CLASS) {
    %!helpers{$name} = $fn;
    return self;
}

multi method context-helper(Str $name --> Helper) {
    return %!helpers{$name};
}

method _handler(--> Callable) {
    $Lock.protect(sub {
        return if $!handler;

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
                next if !$route.match($ctx);

                $route($ctx);
                return;
            }

            $ctx.not-found;
        });

        my Callable $stack = self._prepare-middleware(self.middlewares);
        my $context_class  = %.config<context_class> || Hematite::Context;

        $!handler = Hematite::Handler.new(
            app           => self,
            stack         => $stack,
            context_class => $context_class,
        );
    });

    return $!handler;
}

method _prepare-routes(--> Array) {
    my @routes = self.routes;

    # sub-routers
    for self.groups.kv -> $pattern, $router {
        my @group_routes = $router._prepare-routes($pattern, []);
        @routes.append(@group_routes);
    }

    return @routes;
}
