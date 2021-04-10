#!/usr/bin/env raku

use Test;
use JSON::Fast;

sub MAIN {
    my $cur_dirname = IO::Path.new($?FILE).dirname;
    my %meta        = from-json("{$cur_dirname}/../META6.json".IO.slurp);
    my @provides    = %meta<provides>.values.sort;
    my @lib_files   = find-files("{$cur_dirname}/../lib");

    is-deeply(@provides, @lib_files, '"provides" correctly defined');

    done-testing();
}

sub find-files($dir) {
    my @files;

    for dir($dir) -> $file {
        my $relative_file = $file;

        $relative_file ~~ s/$dir\///;

        next if $relative_file ~~ /^\./;

        if ($file.IO.d) {
            @files.push(|find-files($file));
            next;
        }

        next if $file.IO.extension ne 'rakumod';

        my $final_filename = $file.match(/\/(lib\/.*)$/)[0].Str;

        @files.push($final_filename);
    }

    return [@files.sort];
}
