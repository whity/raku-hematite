# Hematite

[![test](https://github.com/whity/raku-hematite/actions/workflows/test.yml/badge.svg)](https://github.com/whity/raku-hematite/actions/workflows/test.yml)

## Usage

```raku
# psgi file
use Hematite;

my $app = Hematite.new;

# middleware
$app.use(sub ($ctx, $next) {
    # some processing...

    # call next
    $next($ctx);

    # some processing...
});

class TestMiddleware does Callable {
    method CALL-ME($ctx, $next) {
        $next($ctx);
    }
}

$app.use(TestMiddleware.new);

# routes (can define any http method)
$app.GET('/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });
#$app.POST('/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });
#$app.METHOD('get', '/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });

# route with middleware
$app.GET(
    '/with-middleware',
    [sub ($ctx, $next) { say 'route middleware'; $next($ctx); }],
    sub ($ctx) { $ctx.render({'route' => '/with-middleware'}, 'type' => 'json'); }
);

# route with placeholders/captures
$app.GET(
    '/captures/:c1',
    sub {
        say({
            'captures' => $ctx.captures,
            'named-captures' => $ctx.named-captures
        });
    }
);

# route rendering json
$app.GET(
    '/json',
    sub ($ctx) {
        $ctx.render-json(
            {'hello' => 'world'},
        );
    }
);

# route rendering template
$app.GET(
    '/template',
    sub ($ctx) {
        $ctx.render(
            'hello',
            data => { name => 'world', }
        );
    }
);

# route rendering inline template/string
$app.GET(
    '/template-inline',
    sub ($ctx) {
        $ctx.render(
            'hello {{ name }}',
            inline => True,
            data => { name => 'world', }
        );
    }
);


# groups
my $group = $app.group('/group');
$group.GET('/', sub ($ctx) { $ctx.render({'group' => 1}); });

$app;
```

### start crust

```bash
crustup [psgi file]
```

### using a more OO approach

```raku

class ExampleMiddleware does Hematite::Middleware {
    method CALL-ME {
        say 'example-middleware';
        return self.next;
    }
}

class ExampleAction does Hematite::Action {
    method middleware {
        return [
            ExampleMiddleware.create,
        ];
    }

    method CALL-ME {
        return self.render('example action', inline => True);
    }
}

class App is Hematite::App {
    method startup {
        self.use(ExampleMiddleware.create);

        self.GET('/', ExampleAction.create);
        self.POST('/', 'ExampleAction');
    }
}
```

### context helpers

```raku
class Middleware does Hematite::Middleware {
    method CALL-ME {
        self.add-helper('xpty', sub ($ctx) {
            # do something...
        });

        self.next;

        self.remove-helper('xpty');
    }
}

my $app = Hematite::App.new;

# register global context helper
$app.context-helper('xpto', sub ($ctx) { say 'helper...'; });

# register context helpers, directly in the context
$app.use(sub ($ctx, $next) {
    $ctx.add-helper('xptz', sub ($ctx) {
        # do something...
    });

    $next($ctx);

    $ctx.remove-helper('xptz');
});

$app.use(Middleware.create);

# just call the helper from the context
$app.GET('/', sub ($ctx) {
    $ctx.xpto;
    $ctx.xptz;
    $ctx.xpty;
});
```

### websockets

```raku

my $app = Hematite::App.new;

$app.WS('/websocket', sub ($ctx) {
    $ctx.on('ready', sub {
        $ctx.log.info('websocket ready');

        for 1..10 -> $idx {
            $ctx.send('message', "ping {$idx}");
        }

        $ctx.send('close');
    });

    $ctx.on('message', sub ($text) {
        $ctx.log.info('received: ' ~ $text);
    });

    $ctx.on('close', sub {
        $ctx.log.info('websocket closed');
    });
});

# OR

class WSAction does Hematite::Action {
    method CALL-ME {
        self.on('ready', sub {
            self.log.info('websocket ready');

            for 1..10 -> $idx {
                self.send('message', "ping {$idx}");
            }

            self.send('close');
        });

        self.on('message', sub ($text) {
            self.log.info('received: ' ~ $text);
        });

        self.on('close', sub {
            self.log.info('websocket closed');
        });
    }
}

$app.WS('/websocket2', WSAction);
```

## TODO

- better doc
- unit tests
- ...

## Contributing

1. Fork it ( https://github.com/[your-github-name]/raku-hematite/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- whity(https://github.com/whity) André Brás - creator, maintainer
