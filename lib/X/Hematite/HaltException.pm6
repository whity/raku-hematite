use X::Hematite::DetachException;

unit class X::Hematite::HaltException is X::Hematite::DetachException;

method message() returns Str {
    return 'halt exception';
}
