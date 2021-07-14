use MONKEY-SEE-NO-EVAL;
use Crust::Request;

unit class Hematite::Request is Crust::Request;

use JSON::Fast;

has $!body_params  = Nil;
has $!query_params = Nil;

# instance methods

multi method FALLBACK(Str $name where /^accepts\-(\w+)$/ --> Bool) {
    my $type    = ($name ~~ /^accepts\-(\w+)$/)[0];
    my @accepts = self.accepts;

    return @accepts.first(-> $item { $item ~~ /$type/ }) ?? True !! False;
}

method body-parameters(--> Hash) {
    if (!$!body_params.defined) {
        $!body_params = parse-params(callsame.all-pairs);
    }

    # return a clone, not the original structure
    return $!body_params.raku.EVAL;
}

method body-params { return self.body-parameters; }

method query-parameters(--> Hash) {
    if (!$!query_params.defined) {
        my @pairs = callsame.all-pairs;
        $!query_params = parse-params(@pairs);
    }

    # return a clone, not the original structure
    return $!query_params.raku.EVAL;
}

method query-params { return self.query-parameters; }

method is-xhr(--> Bool) {
    my $header = self.header('x-requested-with');

    return False if !$header || $header.lc ne 'xmlhttprequest';
    return True;
}

method accepts(--> Array) {
    my $accepts = self.headers.header('accept') || '';
    my $matches = $accepts ~~ m:g/(\w+\/\w+)\,?/;

    return [] if !$matches;

    $matches = $matches.map(-> $item { $item.Str });

    return $matches.Array;
}

method json {
    my $supply = self.body;
    my $body   = "";

    $supply.tap(-> $chunk { $body ~= $chunk.decode("utf-8"); });
    $supply.wait;

    return from-json($body);
}

# helper functions

sub parse-params(@items --> Hash) {
    my %params = ();
    for @items -> $item {
        my $key = $item.key;
        next if !$key.defined || !$key.chars;

        my $value = $item.value;
        if (%params{$key}:exists) {
            my $cur_value = %params{$key};
            if (!$cur_value.isa(Array)) {
                $value = [$cur_value, $value];
            }
        }

        %params{$key} = $value;
    }

    return %params;
}
