#use Hematite::Exceptions::HTTPException;
#use Hematite::Exceptions::DetachException;
#use Hematite::Exceptions::TemplateNotFoundException;

# load all exceptions files
my $exceptions_dir = $?FILE.IO.absolute.IO.dirname ~ '/Exceptions';
my @files          = $exceptions_dir.IO.dir(test => /:i\.pm6$/);
for @files -> $item {
    my $class = ($item ~~ /(<-[\/]>*)\..*$$/)[0].Str;

    try {
        ::("X::Hematite::{ $class }");

        CATCH {
            my $ex = $_;
            when X::NoSuchSymbol {
                my $require = "Hematite::Exceptions::{ $class }";
                try require ::($require);
            }

            default { say $ex; }
        }
    }
}