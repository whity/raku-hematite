use MONKEY-SEE-NO-EVAL;
use Hematite::Context;

unit class Hematite::Route does Callable;

has Str $.method;
has Str $.pattern;
has Callable $.stack;
has Regex $!re;
has Str $!name;

method new(Str $method, Str $pattern, Callable $stack) {
    return self.bless(
        method  => $method,
        pattern => $pattern,
        stack   => $stack,
    );
}

submethod BUILD(Str :$method, Str :$pattern, Callable :$stack) {
    my Str $re = $pattern.subst(/\/$/, ""); # remove ending slash

    # build regex path
    #   replace ':[word]' by ($<word>)
    #   we can't have subpattern names duplicated, suffix it with the index
    while (my $match = ($re ~~ /:i \:(\w+)/)) {
        my Str $group = ~($match[0]);
        $re ~~ s/\:$group/\(\$\<$group\>=\\w+\)/;
    }

    $re ~= '/?(\?.*)?';

    # replace special chars
    for ('/', '-') -> $char {
        $re ~~ s:g/$char/\\$char/;
    }

    $!re      = EVAL(sprintf('/^%s$/', $re));
    $!method  = $method;
    $!pattern = $pattern;
    $!stack   = $stack;

    return self;
}

multi method name() returns Str { return $!name; }
multi method name(Str $name) returns ::?CLASS {
    $!name = $name;
    return self;
}

method match(Hematite::Context $ctx) returns Bool {
    my $req = $ctx.request;

    if ((self.method eq 'ANY' || self.method eq $req.method) && $req.path ~~ $!re) {
        return True;
    }

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

    return self.stack.($ctx);
}

method _find-captures($match) returns Hash {
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
