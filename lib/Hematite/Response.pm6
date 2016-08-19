use HTTP::Response;

unit class Hematite::Response is HTTP::Response;

multi method charset() returns Str {
    my $content_type = self.header.hash{'Content-Type'}[0];
    my $charset = ($content_type ~~ /\s*charset\=(\w*)/);

    if ($charset) {
        return ~($charset.list[0]);
    }

    return '';
}

multi method charset(Str $value) returns Hematite::Response {
    my $content_type = self.header.hash{'Content-Type'}[0];
    my $type = ($content_type ~~ /(\w+\/\w+)/);
    $content_type = ~($type.list[0]) ~ ', charset=' ~ $value;

    self.field(Content-Type => $content_type);

    return self;
}

# TODO:
#   - multi method content-type() {}
#   - multi method content-type($value) {}
