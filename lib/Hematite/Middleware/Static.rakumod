use Hematite::Middleware;

unit class Hematite::Middleware::Static does Hematite::Middleware;

has Str $.public_dir is required;

method CALL-ME {
    my IO::Path $request_path = "{self.public_dir}/{self.req.path}".IO;

    # if isn't a directory and the file exists, just serve it
    if (!$request_path.d && $request_path.f) {
        self.serve-file($request_path.absolute);
        return;
    }

    # not a static file, continue to the next middleware
    self.next;

    return;
}
