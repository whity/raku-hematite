use Hematite::Context;

unit role Hematite::Action does Callable;

has Hematite::Context $!ctx;

method middleware(--> Array) { []; }

method new($ctx) {
    return self.bless(
        ctx => $ctx,
    );
}

submethod BUILD(:$ctx) {
    $!ctx = $ctx;

    return self;
}

method FALLBACK(Str $name, |args) {
    return $!ctx."{$name}"(|args);
}

method CALL-ME { ... }

method create(--> Capture) {
    return \(
        self.middleware,
        sub ($ctx) {
            return self.new($ctx).();
        }
    );
}
