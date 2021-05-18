unit class Hematite::Context;

use WebSocket::Handle;
use WebSocket::Handshake;
use WebSocket::Frame::Grammar;
use HTTP::Status;
use MIME::Types;
use Logger;
use Hematite::Request;
use Hematite::Response;
use X::Hematite;

my Lock $Lock = Lock.new;

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
has Logger $.log;

subset Helper where .signature ~~ :($ctx, |args);
has Helper %!helpers = ();

has WebSocket::Handle $!sock_handler;
has Callable %!sock_events = ();

# methods
method new($app, Hash $env) {
    return self.bless(
        app => $app,
        env => $env,
    );
}

submethod BUILD(*%args) {
    $!app      = %args<app>;
    $!request  = Hematite::Request.new(%args<env>);
    $!response = Hematite::Response.new(
        200,
        Content-Type => 'text/html;charset=utf-8',
    );

    $!log = Logger.new(
        pattern => '[%d][%X{request_id}][%c] %m%n',
        level   => $!app.log.level,
        output  => $!app.log.output,
        mdc     => $!app.log.mdc.Hash,
        ndc     => $!app.log.ndc.Array,
    );

    self.log.mdc.put(
        'request_id',
        sprintf('%s-%s', $*PID, $*THREAD.id)
    );

    # search for the mime.types file
    $Lock.protect(sub {
        return if $MimeTypes;

        my @mimetype_paths = ('/etc', '/etc/apache2');
        for @mimetype_paths -> $path {
            my $fullpath = $path ~ '/mime.types';
            next if !$fullpath.IO.e;

            $MimeTypes = MIME::Types.new($fullpath);
            last;
        }
    });

    self.log.debug("processing request: " ~ $!request.uri);

    return self;
}

method can(Str $name --> List) {
    my @local = callsame;

    return @local.List if @local.elems;
    return [%!helpers{$name}].List if %!helpers{$name}:exists;

    my $global_helper = self.app.context-helper($name);

    return [$global_helper].List if $global_helper;
    return ();
}

multi method add-helper(Str $name, Helper $fn) {
    %!helpers{$name} = $fn;
    return self;
}

method remove-helper(Str $name --> Helper) {
    return %!helpers{$name}:delete;
}

multi method FALLBACK(Str $name, |args) {
    my $helper = %!helpers{$name};
    return self.$helper(|args) if $helper;

    $helper = self.app.helper($name);
    return self.$helper(|args) if $helper;

    die X::Method::NotFound.new(
        method   => $name,
        typename => self.^name,
    );
}

multi method FALLBACK(Str $name where /^render\-/, |args) {
    my $type = ($name ~~ /^render\-(\w+)$/)[0].Str;
    return self.render(|args, type => $type);
}

method !get-captures(Str $type) {
    return %!captures{$type}.raku.EVAL;
}

method !set-captures(Str $type, $values --> ::?CLASS) {
    if (%!captures{$type}.defined) {
        self.log.debug('captures already setted, skipping it.');
        return self;
    }

    my $copy = $values.raku.EVAL;

    %!captures{$type} = $copy;

    return self;
}

method req(--> Hematite::Request)  { return self.request;  }
method res(--> Hematite::Response) { return self.response; }

# route captures
multi method captures(--> Array) {
    return self!get-captures('list');
}

# route set list capture params
multi method captures(@captures) {
    return self!set-captures('list', @captures);
}

# route named captures
multi method named-captures(--> Hash) {
    return self!get-captures('named');
}

# route set named capture params
multi method named-captures(%captures) {
    return self!set-captures('named', %captures);
}

multi method halt(*%args) {
    die X::Hematite::HaltException.new(status => 500, |%args);
}

multi method halt($body) {
    self.halt(body => $body);
}

multi method halt(Int $status) {
    self.halt(status => $status);
}

multi method halt(Int $status, $body) {
    self.halt(status => $status, body => $body);
}

method not-found() { self.halt(404); }

multi method url-for(Str $url is copy, @captures is copy, *%query --> Str) {
    # if the $url hasn't the initial '/' use has context the current url
    my Str $full_url = "";
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

multi method url-for(Str $url, *%query --> Str) {
    return self.url-for($url, [], |%query);
}

multi method url-for(Str $url is copy, %captures is copy, *%query --> Str) {
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
        self.log.warn("no route found with name: { $name }");
        return;
    }

    return self.url-for($route.pattern, $captures, |%query);
}

multi method url-for-route(Str $name, *%query) {
    return self.url-for-route($name, [], |%query);
}

method !render-to-string($data, %options --> List) {
    my Str $type = %options<type> || 'template';

    %options<type> = $type = $type.lc;

    return self.app.render-handler($type)(
        $data,
        |%options,
        mime_types => $MimeTypes,
    );
}

method render-to-string($data, *%options --> Str) {
    my ($result) = self!render-to-string($data, %options);
    return $result;
}

method render($data, *%options --> ::?CLASS) {
    my ($result, $content_type) = self!render-to-string($data, %options);

    # guess status
    my Int $status = %options<status> || 200;

    self.res.code = $status;
    self.res.body = $result;

    self.res.headers.content-type($content_type);

    return self;
}

method detach() { die X::Hematite::DetachException.new; }

method redirect(Str $url --> ::?CLASS) {
    self.res.code = 302;

    self.res.headers.location($url);

    return self;
}

method redirect-and-detach(Str $url) {
    self.redirect($url);
    self.detach;
}

multi method handle-error(X::Hematite::HaltException $ex --> ::?CLASS) {
    my Callable $handler = self.app.error-handler($ex.status);
    $handler ||= self.app.error-handler(X::Hematite::HaltException);

    $handler(self, |$ex.attributes);

    return self;
}

multi method handle-error(Exception $ex --> ::?CLASS) {
    try {
        my Exception:U $type = $ex.WHAT;
        my @types            = $type.^parents;

        @types.unshift($type);

        my Callable $handler = Nil;
        for @types -> $tp {
            $handler = self.app.error-handler($tp);
            last if $handler;
        }

        $handler(self, exception => $ex,);

        CATCH {
            my Exception $ex = $_;

            when X::Hematite::HaltException {
                self.handle-error($ex);
            }

            when X::Hematite::DetachException {
                # don't do nothing, stop handle error process
            }
        }
    }

    return self;
}

method stream(Callable $fn --> ::?CLASS) {
    my Channel $channel = Channel.new;

    # check in every half a second if the client is still receiving the data,
    # otherwise close the channel
    # we know the client is receiving if the poll is Nil
    my $scheduler = $*SCHEDULER.cue(
        { $channel.close if $channel.poll; },
        every => 0.5,
    );

    # start a new thread and run the passed function
    start {
        my $orig_request_id = self.log.mdc.get('request_id');

        self.log.mdc.put(
            'request_id',
            sprintf('%s-%s', $orig_request_id, $*THREAD.id)
        );

        $fn(sub ($value) { $channel.send($value); });

        CATCH {
            my $ex = $_;

            when X::Hematite::DetachException {
                # Do nothing, detach exception.
            }

            when X::Channel::SendOnClosed {
                # Do nothing, the stream was just closed.
            }

            default {
                self.log.error($ex.gist);
            }
        }

        LEAVE {
            $channel.close;

            self.log.debug('stream closed');
            self.log.mdc.put('request_id', $orig_request_id);
        }
    }.then({
        self.log.debug('stream finished, cancelling the scheduler');
        $scheduler.cancel;
    });

    self.res.body = $channel;

    return self;
}

method serve-file(Str $filepath --> ::?CLASS) {
    # get file extension
    my Str $ext = IO::Path.new($filepath).extension;

    # guess content type
    my Str $content_type = $MimeTypes.type($ext) || 'application/octect-stream';
    self.res.headers.content-type($content_type);

    # serve file
    self.res.body = $filepath.IO.open;

    return self;
}

method upgrade-to-websocket(--> ::?CLASS) {
    my Hash $env = $.request.env;

    # use socket directly is bad idea. But HTTP/2 deprecates
    # `connection: upgrade`. Then, this code may not
    # break on feature HTTP updates.
    my IO::Socket::Async $socket = $env<p6wx.io>;

    die 'no p6wx.io in psgi env' if !$socket;

    if (!($env<HTTP_UPGRADE> ~~ 'websocket')) {
        $.log.warn('no upgrade header in HTTP request');
        return self.halt(400);
    }

    if (!($env<HTTP_SEC_WEBSOCKET_VERSION> ~~ /^\d+$/)) {
        $.log.warn(
            (
                'invalid websocket version...',
                'draft version of websocket not supported.',
            ).join,
        );

        return self.halt(400);
    }

    my $ws_key = $env<HTTP_SEC_WEBSOCKET_KEY>;

    if (!$ws_key) {
        $.log.warn('no HTTP_SEC_WEBSOCKET_KEY');
        return self.halt(400);
    }

    my $accept = make-sec-websocket-accept($ws_key);

    $!sock_handler  = WebSocket::Handle.new(socket => $socket);
    $.response.code = 101;

    $.response.headers.from-hash({
        Connection           => 'Upgrade',
        Upgrade              => 'websocket',
        Sec-WebSocket-Accept => $accept,
    });

    $.response.body = supply {
        $.log.debug('handshake succeded');

        my $buf;

        whenever $socket.Supply(:bin) -> $got {
            $buf ~= $got.decode('latin1');

            loop {
                my $m = WebSocket::Frame::Grammar.subparse($buf);

                if (!$m) {
                    # maybe, frame is partial. maybe...
                    $.log.debug('frame is partial');
                    last;
                }

                my $frame = $m.made;

                $.log.debug("got frame {$frame.opcode}, {$frame.fin.Str}");

                $buf = $buf.substr($m.to);

                given $frame.opcode {
                    when (WebSocket::Frame::TEXT) {
                        $.log.debug("got text frame");
                        self.on('message').(
                            $frame.payload.encode('latin1').decode('utf-8')
                        );
                    }
                    when (WebSocket::Frame::DOCLOSE) {
                        $.log.debug("got close frame");
                        self.on('close').();
                        try $!sock_handler.close;
                        done;
                    }
                    when (WebSocket::Frame::PING) {
                        $.log.debug("got ping frame");
                        $!sock_handler.pong;
                    }
                    when (WebSocket::Frame::PONG) {
                        $.log.debug("got pong frame");
                    }
                    default {
                        $.log.debug("GOT $_");
                    }
                }
            }

            CATCH {
                default {
                    my $ex  = $_;
                    my $msg = sprintf(
                        "error in websocket processing: %s\n%s",
                        $ex.Str,
                        $ex.backtrace.full,
                    );

                    $.log.error($msg);

                    done;
                }
            }
        }

        self.on('ready').();

        ();
    };

    return self;
}

multi method on(Str $event, Callable $fn --> ::?CLASS) {
    die 'No websocket started' if !$!sock_handler;

    %!sock_events{$event} = $fn;
    return self;
}

multi method on(Str $event --> Callable) {
    die 'No websocket started' if !$!sock_handler;

    return %!sock_events{$event} // sub (*@args) {};
}

method send(Str $type is copy, $value?) {
    die 'No websocket to send message to' if !$!sock_handler;

    $type = 'text' if $type eq 'message';

    return $!sock_handler."send-{$type}"($value) if $value.defined;
    return $!sock_handler."send-{$type}"();
}
