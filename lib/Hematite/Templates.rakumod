unit class Hematite::Templates does Callable;

use Template::Mustache;
use X::Hematite;

has Str $.directory;
has Str $.extension;
has Str %!cache = ();

submethod BUILD(Str :$directory, Str :$extension) {
    $!directory = $directory || $*CWD ~ '/templates';

    $!extension = $extension || '.mustache';
    if ( !$!extension.substr-eq(".", 0) ) {
        $!extension = ".{$!extension}";
    }

    return self;
}

method render-string(Str $template, :%data = {}, *%args --> Str) {
    my $format = %args<format>;

    return Template::Mustache.render(
        $template,
        %data.clone,
        from      => [self.directory],
        extension => ".{$format}{self.extension}",
    );
}

method render-template(Str $name is copy, :%data = {}, *%args --> Str) {
    my $format = %args<format>;

    $name ~= ".{$format}";

    # check in cache
    my Str $template = %!cache{$name};
    if (!$template) {
        # build full template file path and check if exists
        my $filepath = "{self.directory}/{$name}";

        $filepath ~= self.extension;

        # if file doesn't exists, throw error
        $filepath = $filepath.IO;
        if (!$filepath.e) {
            die X::Hematite::TemplateNotFoundException.new(
                path => $filepath.Str
            );
        }

        $template      = $filepath.slurp;
        %!cache{$name} = $template;
    }

    return self.render-string($template, data => %data, |%args);
}

# render($template-name) ; render($template-string, inline => True)
method render($data, *%args --> List) {
    my $str = ($data || '').Str;

    %args<format> ||= 'html';

    my $content_type = %args<mime_types>.type(%args<format>);

    return (self.render-string($str, |%args), $content_type) if %args<inline>;
    return (self.render-template($str, |%args), $content_type);
}

method CALL-ME($data, |args) {
    return self.render($data, |%(args));
}
