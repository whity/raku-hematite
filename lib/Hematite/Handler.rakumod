unit class Hematite::Handler does Callable;

use Cookie::Baker;
use Hematite::Context;

has $.app;
has Callable $.stack;
has Hematite::Context:U $!ctx_class;

submethod BUILD(*%args) {
    $!app       = %args<app>;
    $!stack     = %args<stack>;
    $!ctx_class = %args<context_class>;
}

method CALL-ME(Hash $env) {
    my $ctx = $!ctx_class.new(self.app, $env);

    try {
        # call middleware stack
        self.stack.($ctx);

        CATCH {
            my Exception $ex = $_;

            default {
                $ctx.handle-error($ex);
            }
        }
    }

    for $ctx.res.cookies.kv -> $name, $attrs {
        my $value = $attrs<value>:delete;
        my $bake  = bake-cookie($name, $value, |%($attrs));

        $ctx.res.headers.add('set-cookie', $bake);
    }

    # return context response
    my Int $code = $ctx.res.code;
    my $body     = $ctx.res.body;

    my @headers = ();
    for $ctx.res.headers.Hash.keys -> $name {
        next if $name eq 'content-type';

        my $value = $ctx.res.header($name);
        next if !$value.defined;

        @headers.push($name => $value);
    }

    my Str $content_type = $ctx.res.headers.content-type || 'text/html';
    my $charset          = $content_type ~~ m:i/charset\=(<[\w-]>+)/;

    $content_type = "{ $content_type };charset=utf-8" if !$charset;

    @headers.push('content-type' => $content_type);

    $body = $body.defined ?? $body !! '';
    $body = [$body] if $body.isa(Str);

    return [$code, @headers, $body];
}
