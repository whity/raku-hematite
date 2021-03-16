use Hematite::Context;

unit role Hematite::Middleware does Callable;

has Hematite::Context $!ctx;
has Callable $!next;

method new(Hematite::Context $ctx, Callable $next, *%args) {
    return self.bless(
        ctx  => $ctx,
        next => $next,
        args => %args,
    );
}

submethod BUILD(:$ctx, :$next, :%args) {
    $!ctx  = $ctx;
    $!next = $next;

    for self.^attributes -> $attribute {
        next if !$attribute.has_accessor;

        my $name = ($attribute.name ~~ /\$\!(\w+)$/)[0].Str;
        next if !(%args{$name}:exists);

        $attribute.set_value(self, %args{$name});
    }

    return self;
}

method FALLBACK(Str $name, |args) {
    return $!ctx."{$name}"(|args);
}

method CALL-ME { ... }

method next {
    return $!next($!ctx);
}

method create(*%args --> Callable) {
    return sub ($ctx, $next) {
        return self.new($ctx, $next, |%args).();
    };
}
