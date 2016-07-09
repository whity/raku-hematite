use Hematite::App;
use Hematite::Exceptions;

unit class Hematite;

method new(Hematite:U: |args) {
    return Hematite::App.new(|@(args));
}
