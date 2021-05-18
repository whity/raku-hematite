unit class Hematite::Route does Callable;

use MONKEY-SEE-NO-EVAL;

use Hematite::Context;

has Str $.method;
has Str $.pattern;
has Callable $.stack;
has Regex $!re;
has Str $!name;
has Bool $!is_websocket;

method new(Str $method, Str $pattern, Callable $stack, *%options) {
    return self.bless(
        method  => $method,
        pattern => $pattern,
        stack   => $stack,
        |%options,
    );
}

submethod BUILD(Str :$method, Str :$pattern, Callable :$stack, *%options) {
    my Str $re = $pattern.subst(/\/$/, ""); # remove ending slash

    # build regex path
    #   replace ':[word]' by ($<word>)
    while (my $match = ($re ~~ /:i \:(\w+)/)) {
        my Str $group = $match[0].Str;
        $re ~~ s/\:$group/\(\$\<$group\>=\\w+\)/;
    }

    $re ~= '/?(\?.*)?';

    # replace special chars
    for ('/', '-') -> $char {
        $re ~~ s:g/$char/\\$char/;
    }

    $!re           = EVAL(sprintf('/^%s$/', $re));
    $!method       = $method;
    $!pattern      = $pattern;
    $!stack        = $stack;
    $!is_websocket = %options<websocket> // False;

    return self;
}

multi method name(--> Str) { return $!name; }
multi method name(Str $name --> ::?CLASS) {
    $!name = $name;
    return self;
}

method match(Hematite::Context $ctx --> Bool) {
    my $req = $ctx.request;

    return False if !($req.path ~~ $!re);
    return True if self.method eq 'ANY';
    return True if self.method eq $req.method;

    return False;
}

method CALL-ME(Hematite::Context $ctx) {
    # guess captures
    my $match    = $ctx.request.path.match($!re);
    my %captures = self._find-captures($match);

    if (%captures<list>.elems > 0) {
        $ctx.log.debug("captures found: ");
        $ctx.log.debug(" - named: " ~ ~(%captures<named>));
        $ctx.log.debug(" - list: " ~ ~(%captures<list>));
    }

    # set captures on context
    $ctx.named-captures(%captures<named>);
    $ctx.captures(%captures<list>);

    $ctx.upgrade-to-websocket if $!is_websocket;

    return self.stack.($ctx);
}

method _find-captures($match --> Hash) {
    my @groups = $match.list;

    my @list  = ();
    my %named = ();

    for @groups -> $group {
        my %named_caps = $group.hash;
        if (!%named_caps) {
            @list.push($group.Str);
            next;
        }

        # check if group.hash has keys, if not it's a simple group
        for %named_caps.kv -> $key, $value {
            next if !$key;

            my $vl = $value.Str;
            @list.push($vl);

            if (%named{$key}:exists) {
                my $cur_value = %named{$key};
                if (!$cur_value.isa(Array)) {
                    $cur_value = [$cur_value];
                }
                $cur_value.push($vl);
                %named{$key} = $cur_value;
                next;
            }

            %named{$key} = $vl;
        }

        # check group.list and add the captures
        my %result = self._find-captures($group);

        @list.append(@(%result<list>));
        %named.append(%(%result<named>));
    }

    return {
        'list'  => @list,
        'named' => %named,
    };
}
