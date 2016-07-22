# Hematite

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  i18n:
    github: whity/crystal-i18n
```

## Usage

```perl6
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
    method CALL($ctx, $next) {
        $next($ctx);
    }
}

$app.use(TestMiddleware.new);

# helpers (request context)
$app.helper('xpto', sub { say 'helper...'; });

# routes (can define any http method)
$app.GET('/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });
#$app.POST('/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });
#$app.METHOD('get', '/', sub ($ctx) { $ctx.render({'route' => '/'}, 'type' => 'json'); });

$app.GET(
    '/with-middleware',
    [sub ($ctx, $next) { say 'route middleware'; $next($ctx); }],
    sub ($ctx) { $ctx.render({'route' => '/with-middleware'}, 'type' => 'json'); }
);

$app.GET(
    '/captures/:c1',
    sub ($ctx) {
        $ctx.render(
            {
                'captures' => $ctx.captures,
                'named-captures' => $ctx.named-captures
            },
        );
    }
);

# groups
my $group = $app.group('/group');
$group.GET('/', sub ($ctx) { $ctx.render({'group' => 1}); });

$app = $app.handler;
```

### start crust

```bash
crustup [psgi file]
```


## TODO

- logging
- ...

## Contributing

1. Fork it ( https://github.com/[your-github-name]/perl6-hematite/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- whity(https://github.com/whity) André Brás - creator, maintainer
