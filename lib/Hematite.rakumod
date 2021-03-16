use Hematite::App;

unit class Hematite;

method new(::?CLASS:U: |args --> Hematite::App) {
    return Hematite::App.new(|%(args));
}
