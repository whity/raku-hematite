#!/usr/bin/env raku

use Test;
use Test::META;

sub MAIN {
    meta-ok();
    done-testing();
}
