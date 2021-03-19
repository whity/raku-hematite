use X::Hematite::Exception;

unit class X::Hematite::DetachException is X::Hematite::Exception;

method message(--> Str) {
    return 'detach exception';
}
