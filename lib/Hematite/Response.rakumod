unit class Hematite::Response;

class Headers {
    has %!headers = ();

    submethod BUILD(*%headers) {
        return self.from-hash(%headers);
    }

    multi method FALLBACK(Str $name, |c) {
        return self.header($name, |c);
    }

    method header(Str $name, *@values) {
        return self.remove($name).add($name, |@values) if @values.elems;

        my Array $headers = %!headers{$name.lc} // [];

        return if !$headers.elems;
        return $headers.join(', ');
    }

    method remove(Str $name --> ::?CLASS) {
        %!headers{$name.lc}:delete;
        return self;
    }

    method add(Str $name, *@values --> ::?CLASS) {
        %!headers{$name.lc} //= [];
        %!headers{$name.lc}.append(@values);

        return self;
    }

    method append(Str $name, Str $value) {
        my Str $old       = self.header($name);
        my Str $new_value = $old.defined ?? "{$old}, {$value}" !! $value;

        return self.header($name, $new_value);
    }

    method from-hash(%headers --> ::?CLASS) {
        for %headers.kv -> $k, $v {
            self.add($k, |$v.Array);
        }

        return self;
    }

    method clear(--> ::?CLASS) {
        %!headers = ();
        return self;
    }

    method Array(--> Array) {
        my @headers = ();

        for %!headers.kv -> $k, $v {
            @headers.push($k => $_) for $v;
        }

        return @headers;
    }

    method Hash(--> Hash) {
        return %!headers.raku.EVAL;
    }
}

has $.body is rw;
has Int $.code is rw;
has %.cookies = ();
has Headers $.headers;

method new(Int $code = 200, $body?, *%headers) {
    return self.bless(
        code    => $code,
        body    => $body,
        headers => %headers,
    );
}

submethod BUILD(:$code, :$body, :%headers) {
    $!code    = $code;
    $!body    = $body;
    $!headers = Headers.new(|%headers);

    return self;
}

method header(Str $name, *@values) {
    return $.headers.header($name, |@values);
}
