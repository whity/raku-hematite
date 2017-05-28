use Hematite::App;

unit class Hematite;

method new(Hematite:U: |args) {
    return Hematite::App.new(|%(args));
}
