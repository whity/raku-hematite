sub resolve($name, $context) {

}

class Node {
    has @.children;
    has Bool $.creates_scope is rw;

    method new($fragment) {
        return self.bless(
            fragment => $fragment
        );
    }

    submethod BUILD(:$fragment) {
        @!children = ();
        $!creates_scope = False;
        self.process-fragment($fragment);
    }

    method process-fragment($fragment) { return; }
    method enter-scope() { return; }
    method render($context) { return; }
    method exit-scope() { return; }

    method render-children($context, $children=Nil) {
        if (!$children.defined) {
            $children = self.children;
        }

        my $render_child = sub ($child) {
            my $child_html = $child.render($context);
            if ($child_html) {
                return ~($child_html);
            }

            return '';
        };

        return $children.map($render_child).join('');
    }
}

class ScopableNode is Node {
    submethod BUILD() {
        self.creates_scope = True;
    }
}

class Root is Node {
    method render($context) {
        return self.render-children($context);
    }
}

class Variable is Node {
    has Str $.name;

    method process-fragment($fragment) {
        self.name = $fragment;
    }

    method render($context) {
        return resolve(self.name, $context);
    }
}

#my $x = ScopableNode.new(11);
#my @a = (1,2,3);
#my $s = sub ($item) { say $item; };
#@a.map($s);
