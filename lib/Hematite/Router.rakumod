unit class Hematite::Router;

use Hematite::Route;
use Hematite::Context;
use Hematite::Action;
use X::Hematite;

has Callable @!middlewares    = ();
has Hematite::Router %!groups = ();
has Hematite::Route @!routes  = ();

method new {
    return self.bless;
}

# fallback for the http method
method FALLBACK($name where /^<[A .. Z]>+$/, |args) {
    return self.METHOD($name, |@(args));
}

method middlewares(--> Array) {
    my @copy = @!middlewares;
    return @copy;
}

method routes(--> Array) {
    return @!routes.clone;
}

method groups(--> Hash) {
    return %!groups.clone;
}

multi method use(Callable:D $middleware --> ::?CLASS) {
    @!middlewares.push($middleware);
    return self;
}

method group(Str $pattern is copy --> ::?CLASS) {
    if ($pattern.substr(0, 1) ne "/") {
        $pattern = "/" ~ $pattern;
    }
    $pattern ~~ s/\/$//; # remove ending slash

    my Hematite::Router $group = %!groups{$pattern};
    if (!$group) {
        $group = %!groups{$pattern} = Hematite::Router.new;
    }

    return $group;
}

multi method METHOD(Str $method, Str $pattern, Callable $fn --> Hematite::Route) {
    return self!create-route($method, $pattern, self!middleware-runner($fn));
}

multi method METHOD(Str $method, Str $pattern, @middlewares is copy, Callable $fn --> Hematite::Route) {
    # prepare middleware
    my Callable $stack = self._prepare-middleware(@middlewares, $fn);

    # create route
    return self!create-route($method, $pattern, $stack);
}

multi method METHOD(Str $method, Str $pattern, Str $action) {

    # first, check if the action module is already loaded
    #   if not, lets try to load it.

    my $module;

    try {
        $module = ::($action);

        CATCH {
            when X::NoSuchSymbol {
                require $action;
                $module = ::($action);
            }
        }
    };

    if ($module.does(Hematite::Action)) {
        return self."{$method}"($pattern, |$module.create);
    }

    return self."{$method}"($pattern, $module);
}

method !create-route(Str $method, Str $pattern is copy, Callable $fn --> Hematite::Route) {
    # add initial slash to pattern
    if ($pattern.substr(0, 1) ne "/") {
        $pattern = "/" ~ $pattern;
    }

    my Hematite::Route $route = Hematite::Route.new($method.uc, $pattern, $fn);
    @!routes.push($route);

    return $route;
}

method _prepare-routes(Str $parent_pattern, @middlewares is copy --> Array) {
    my @routes = [];

    @middlewares.append(@!middlewares);

    # create routes with the router middleware
    for @!routes -> $route {
        my $stack = self._prepare-middleware(@middlewares, $route.stack);
        @routes.push(
            Hematite::Route.new(
                $route.method,
                $parent_pattern ~ $route.pattern,
                $stack
            )
        );
    }

    # sub-routers
    for %!groups.kv -> $pattern is copy, $router {
        $pattern = $parent_pattern ~ $pattern;
        my @group_routes = $router._prepare-routes($pattern, @middlewares);
        @routes.append(@group_routes);
    }

    return @routes;
}

method _prepare-middleware(@middlewares, Callable $app? --> Callable) {
    my Callable $stack = $app;
    for @middlewares.reverse -> $mdw {
        $stack = self!middleware-runner($mdw, $stack);
    }

    return $stack;
}

method !middleware-runner(Callable $mdw, Callable $next? --> Block) {
    my Callable $tmp_next = $next || sub {};

    return sub (Hematite::Context $ctx) {
        try {
            my Int $arity = Nil;
            if ($mdw.isa(Code)) {
                $arity = $mdw.arity;
            }
            else {
                my ($method) = $mdw.can('CALL-ME');
                $arity = $method.arity - 1;
            }

            given $arity {
                when 2 { $mdw($ctx, $tmp_next); }
                when 1 { $mdw($ctx); }
                default { $mdw(); }
            }

            # catch http exceptions and detach
            CATCH {
                my $ex = $_;

                when X::Hematite::HaltException {
                    $ctx.handle-error($ex);
                }

                when X::Hematite::DetachException {
                    # don't do nothing, stop current middleware process
                }
            }
        }
    };
}
