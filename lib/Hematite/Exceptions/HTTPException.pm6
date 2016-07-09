unit class X::Hematite::HTTPException is Exception;

has %!attributes = ();

submethod BUILD(*%args) {
    %!attributes = %args;
}

method FALLBACK(Str $name, |args) {
    return %!attributes{$name};
}

method message() {
    return "HTTPException(" ~ %!attributes.keys.map({ "$( $_ ): $( %!attributes{$_} )" }).join(", ") ~ ")";
}
