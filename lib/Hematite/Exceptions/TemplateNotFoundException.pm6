unit class X::Hematite::TemplateNotFoundException is Exception;

has Str $.path;

submethod BUILD(:$path) {
    $!path = $path;
}

method message() {
    return "TemplateNotFoundException({ self.path })";
}