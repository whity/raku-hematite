use MONKEY-SEE-NO-EVAL;
use HTTP::Status;
use Hematite::Request;
use Hematite::Response;
use Hematite::Exceptions;
use JSON::Fast;
use MIME::Types;

unit class Hematite::Context;

# static vars
my MIME::Types $MimeTypes;

# instance vars
has $.app;
has Hematite::Request $.request;
has Hematite::Response $.response;
has %!captures = (
    'list'  => Nil,
    'named' => Nil
);
has %.stash = ();

# methods
method new($app, Hash $env) {
    return self.bless(
        app => $app,
        env => $env,
    );
}

submethod BUILD(*%args) {
    $!app      = %args{'app'};
    $!request  = Hematite::Request.new(%args{'env'});
    $!response = Hematite::Response.new(200, Content-Type => 'text/html');

    # search for the mime.types file
    if (!$MimeTypes) {
        my @mimetype_paths = ('/etc', '/etc/apache2');
        for @mimetype_paths -> $path {
            my $fullpath = $path ~ '/mime.types';
            if ($fullpath.IO.e) {
                $MimeTypes = MIME::Types.new($fullpath);
                last;
            }
        }
    }

    say $!request.uri;

    return self;
}

method FALLBACK(Str $name, |args) {
    my $helper = self.app.helper($name);
    return $helper(self, |@(args));
}

method !get-captures(Str $type) {
    return EVAL(%!captures{$type}.perl);
}

method !set-captures(Str $type, $values) {
    if (%!captures{$type}.defined) {
        # TODO: throw error
        return;
    }

    my $copy = EVAL($values.perl);
    %!captures{$type} = $copy;
    return;
}

# route captures
multi method params() returns Array {
    return self!get-captures('list');
}

# route set list capture params
multi method captures(@captures) {
    return self!set-captures('list', @captures);
}

# route named captures
multi method named-captures() returns Hash {
    return self!get-captures('named');
}

# route set named capture params
multi method named-captures(%captures) {
    return self!set-captures('named', %captures);
}

multi method halt(*%args) {
    my $status = %args{'status'} ||= 500;

    # check for status error handler
    my $handler = self.app.error-handler($status);
    if (!$handler) {
        $handler = self.app.error-handler('halt');
    }

    $handler(self, |%args);

    self.detach;
}

multi method halt(Int $status) {
    self.halt(status => $status);
}

multi method halt(Str $body) {
    self.halt(body => $body);
}

multi method halt(Int $status, Str $body) {
    self.halt(status => $status, body => $body);
}

multi method halt(Int $status, %headers is copy, Str $body) {
    self.halt(status => $status, headers => $(%headers), body => $body);
}

method not-found() { self.halt(404); }

method try-catch(Block :$try, Block :$catch?, Block :$finally?) {
    try {
        $try();

        CATCH {
            my $ex = $_;

            when X::Hematite::DetachException {
                $ex.rethrow;
            }

            default {
                if (!$catch) {
                    $ex.rethrow;
                }

                $catch($ex);
            }
        }

        LEAVE {
            if ($finally) {
                $finally();
            }
        }
    }

    return;
}

multi method url-for(Str $url is copy, @captures is copy, *%query) returns Str {
    # if the $url hasn't the initial '/' use has context the current url
    my $full_url = "";
    if ( $url ~~ /^\// ) { # absolute
        $full_url = self.request.base;
        $full_url = $full_url.subst(/\/$/, "");
    }
    else { # relative
        $full_url = self.request.uri ~ '/';
    }

    # replace captures :w+
    while (@captures.elems > 0 && (my $match = ($url ~~ /:i (\:\w+)/))) {
        my Str $group = ~($match[0]);
        my $value = @captures.shift;
        $url ~~ s/$group/$value/;
    }
    $full_url ~= $url;

    # add query string
    my Str $querystring = '';
    for %query.kv -> $key, $value {
        my $tmp_value = $value;
        if (!$tmp_value.isa(Array)) {
            $tmp_value = [$tmp_value];
        }

        for @($tmp_value) -> $vl {
            if ($querystring.chars > 0) {
                $querystring ~= '&';
            }
            $querystring ~= "$( $key )=$( $vl )";
        }
    }
    if ($querystring.chars > 0) {
        $full_url ~= '?' ~ $querystring;
    }

    return $full_url;
}

multi method url-for(Str $url, *%query) returns Str {
    return self.url-for($url, [], |%query);
}

multi method url-for(Str $url is copy, %captures is copy, *%query) returns Str {
    # replace captures
    for %captures.kv -> $key, $value {
        my $tmp_value = $value;
        if (!$tmp_value.isa(Array)) {
            $tmp_value = [$tmp_value];
        }

        while ($tmp_value.elems > 0 && (my $match = ($url ~~ /:i (\:$key)/))) {
            my Str $group = ~($match[0]);
            my $value = $tmp_value.shift;
            $url ~~ s/$group/$value/;
        }
    }

    return self.url-for($url, |%query);
}

multi method url-for-route(Str $name, $captures, *%query) {
    my $route = self.app.get-route($name);
    if ( !$route ) {
        # TODO: log warn
        return;
    }

    my $pattern = $route.pattern;
    return self.url-for($pattern, $captures, |%query);
}

multi method url-for-route(Str $name, *%query) {
    return self.url-for-route($name, [], |%query);
}

# method render(Str $template, *%options) {}
#   options:
#       - as_string => by default False, otherwise just return the string doesn't set the response
#       - format    => by default 'html', the full template name to search will be $template.$format
#                      this also affects the response content-type

# method render-json($data, *%options) {}
#   options:
#       - as_string => by default False, otherwise just return the string doesn't set the response

method render-to-string($data, *%options) {
    my $type   = lc(%options{'type'} // 'template');
    my $format = lc(%options{'format'} // 'html');

    if ($type ne 'json') {
        die('render not implemented yet');
    }

    return to-json($data);
}

method render($data, *%options) {
    my $result = self.render-to-string($data, |%options);

    my $type   = lc(%options{'type'} // 'template');
    my $format = lc(%options{'format'} // 'html');
    my $content_type = $type eq 'template' ?? $format !! $type;
    $content_type = $MimeTypes.type($content_type);

    # set content-type
    self.response.field(Content-Type => $content_type);
    self.response.content = $result;

    return;
}

method detach() { X::Hematite::DetachException.new.throw; }

method redirect(Str $url) {
    self.response.set-code(302);
    self.response.field(location => $url);

    return;
}

method redirect-and-detach(Str $url) {
    self.redirect($url);
    self.detach;
}

multi method handle-error(Str $type, *%args) {
    try {
        my $handler = self.app.error-handler($type);
        if (!$handler) {
            die("invalid error handler: $( $type )");
        }

        $handler(self, |%args);

        CATCH {
            my $ex = $_;

            when X::Hematite::DetachException {
                # don't do nothing, stop handle error process
            }
        }
    }

    return;
}

#multi method handle-error(Exception $ex) {
#    my $handler_name = $ex.WHAT.gist;
#    $handler_name ~~ s:g/\(|\)//;
#
#    my $handler = self.app.error-handler($handler_name);
#    if (!$handler) {
#        $handler_name = "default";
#    }
#
#    self.handle-error($handler_name, exception => $ex);
#
#    return;
#}
