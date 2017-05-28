use Cookie::Baker;
use Hematite::Context;

unit class Hematite::Handler does Callable;

has $.app;
has Callable $.stack;

method CALL-ME(Hash $env) {
    my $ctx = Hematite::Context.new(self.app, $env);

    try {
        # call middleware stack
        self.stack.($ctx);

        CATCH {
            my $ex = $_;

            default {
                $ctx.handle-error('unexpected', exception => $ex);
            }
        }
    }

    for $ctx.res.cookies.kv -> $name, $attrs {
        my $value = $attrs{'value'}:delete;
        my $bake  = bake-cookie($name, $value, |%($attrs));
        if ( $ctx.res.header.field('Set-Cookie') ) {
            $ctx.res.header.push-field(Set-Cookie => $bake);
            next;
        }

        $ctx.res.header.field(Set-Cookie => $bake);
    }

    # return context response
    my $status  = $ctx.response.code;
    my $body    = $ctx.response.content;

    my @headers = ();
    for $ctx.response.header.hash.kv -> $name, $value {
        if ($name eq 'Content-Type') { next; }

        for $value.list -> $vl {
            @headers.push($name => $vl);
        }
    }

    # set content-type charset if not present
    my $charset = $ctx.response.charset || 'utf8';
    my $content_type = $ctx.response.content-type || 'text/html';
    $content_type = "{ $content_type }, charset={ $charset }";
    @headers.push('Content-Type' => $content_type);

    # body
    if (!$body.isa(Channel) && !$body.isa(IO::Handle)) {
        if (!$body.isa(Array)) {
            $body = Array.new($body.defined ?? $body !! "");
        }
    }

    return $status, @headers, $body;
}