class POFile::Entry {...}
class POFile {...}

class POFile::IncorrectIndex is Exception {
    has $.index;
    has $.max;

    method message() {
        "Index $!index is out PO file, must be between 1 and $!max"
    }
}
class POFile::IncorrectKey is Exception {
    has $.key;

    method message() {
        "Key $!key is not present in PO file"
    }
}
class POFile::CannotParse is Exception {
    has Int $.line-number is required;
    has Str $.problem is required;
    method message() {
        "Failed to parse .po file at line $!line-number: $!problem"
    }
}

grammar POFile::Parser {
    token TOP {
        [<PO-rule> | <obsolete-message>]* %% "\n"*
        [ $ || <.error('unrecognied syntax')> ]
    }
    token obsolete-message { '#~ ' <comment-text> "\n"? }
    token PO-rule-or-error {
        <PO-rule> \n* [ $ || <.error('unrecognied syntax')> ]
    }
    token PO-rule {
        <comment>*
        [ \n <.error('comment must not be seperated from block by an empty line')> ]?
        <block>
    }
    token block { <msgctxt>? <msgid> <msgid-plural>? [<msgstr>+ %% "\n"+] }
    proto token comment                        { * }
          token comment:sym<source-ref>        { '#: ' <comment-text> "\n" }
          token comment:sym<extracted>         { '#. ' <comment-text> "\n" }
          token comment:sym<translator>        { '# '  <comment-text> "\n" }
          token comment:sym<format-directive > { '#, ' <comment-text> "\n" }
          token comment:sym<previous-string>   { '#| ' <fuzzy-marker> ' ' <comment-text> "\n" }

          token fuzzy-marker { 'msgid' | 'msgctxt' }
    token msgctxt { 'msgctxt ' <item-text> "\n"  }
    token msgid { 'msgid ' <item-text> "\n"  }
    token msgid-plural { 'msgid_plural ' <item-text> "\n"  }
    token msgstr { 'msgstr' <pluralizer>? ' ' <item-text> }
    token pluralizer { '[' \d+ ']' }
    token comment-text { <-[\n]>* }
    token item-text { <long-form> | <-[\n]>+ }
    token long-form { '""' "\n" <quoted-str>+ % "\n" }
    token quoted-str { '"' [<escaped> | <-["]>]* '"' }
    token escaped { '\"' };
    method error($message) {
        die POFile::CannotParse.new:
                line-number => self.orig.substr(0, self.pos).split(/\n/).elems,
                problem => $message;
    }
}

class PO::Actions {
    method TOP($/) {
        my @obsolete-messages = $<obsolete-message>>>.made;
        my @PO;
        for $<PO-rule> -> $rule {
            my %args = $rule.made;
            %args{'msgid'} = po-unquote(%args{'msgid'});
            if %args{'msgid-plural'}.defined {
                %args{'msgid-plural'} = po-unquote(%args{'msgid-plural'});
            }
            my $msgstr = %args{'msgstr'};
            $msgstr = $msgstr ~~ Str ?? po-unquote($msgstr) !! $msgstr.map({ po-unquote($_) }).Array;
            %args{'msgstr'} = $msgstr;
            @PO.push: POFile::Entry.new(|%args);
        }
        make (@PO, @obsolete-messages);
    }

    method PO-rule-or-error($/) {
        make $<PO-rule>.ast;
    }

    method PO-rule($/) {
        my @args;
        my ($reference = '', $extracted   = '', $comment = '',
            $format    = '', $fuzzy-msgid = '', $fuzzy-msgctxt = '');

        # We detect comments line by line, so to gather every e.g.
        # translator comment under one value, we are concatenating results here
        for $<comment> {
            my $comment-pair = $_.made;
            given $comment-pair.key {
                when 'reference' {
                    $reference ~= $comment-pair.value;
                }
                when 'extracted' {
                    $extracted ~= $comment-pair.value;
                }
                when 'comment' {
                    $comment ~= $comment-pair.value;
                }
                when 'format-style' {
                    $format ~= $comment-pair.value;
                }
                when 'fuzzy-msgid' {
                    $fuzzy-msgid ~= $comment-pair.value;
                }
                when 'fuzzy-msgctxt' {
                    $fuzzy-msgctxt ~= $comment-pair.value;
                }
            }
        }

        @args.push(Pair.new('reference', $reference)) if $reference;
        @args.push(Pair.new('extracted', $extracted)) if $extracted;
        @args.push(Pair.new('comment', $comment)) if $comment;
        @args.push(Pair.new('format-style', $format)) if $format;
        @args.push(Pair.new('fuzzy-msgid', $fuzzy-msgid)) if $fuzzy-msgid;
        @args.push(Pair.new('fuzzy-msgctxt', $fuzzy-msgctxt)) if $fuzzy-msgctxt;
        @args.push(|$<block>.made);
        make @args;
    }

    method comment:sym<source-ref>($/)       { make Pair.new('reference',    ~$<comment-text>) }
    method comment:sym<extracted>($/)        { make Pair.new('extracted',    ~$<comment-text>) }
    method comment:sym<translator>($/)       { make Pair.new('comment',      ~$<comment-text>) }
    method comment:sym<format-directive>($/) { make Pair.new('format-style', ~$<comment-text>) }
    method comment:sym<previous-string>($/)  {
        my $is-id = $<fuzzy-marker> eq 'msgid';
        make Pair.new($is-id ?? 'fuzzy-msgid' !! 'fuzzy-msgctxt', ~$<comment-text>);
    }

    method block($/) {
        my @args;
        with $<msgctxt> {
            @args.push(Pair.new('msgctxt', $_.made));
        }
        @args.push(Pair.new('msgid', $<msgid>.made));
        with $<msgid-plural> {
            @args.push(Pair.new('msgid-plural', $<msgid-plural>.made));
            @args.push(Pair.new('msgstr', $<msgstr>.map(*.made).Array));
        } else {
            @args.push(Pair.new('msgstr', $<msgstr>[0].made));
        }
        make @args;
    }

    method msgctxt($/)      { make $<item-text>.made }
    method msgid($/)        { make $<item-text>.made }
    method msgid-plural($/) { make $<item-text>.made }
    method msgstr($/)       { make $<item-text>.made }

    method item-text($/) {
        with $<long-form> {
            make $_<quoted-str>.map(*.substr(1, *-1)).join;
        } else {
            make ~$/.substr(1, *-1);
        }
    }

    method obsolete-message($/) { make ~$<comment-text> }
}

class POFile::Entry {
    # msgid
    has Str $.msgid is rw;
    # msgid_plural
    has Str $.msgid-plural is rw;
    # msgstr, plural or single
    subset MsgStr where Array|Str;
    has MsgStr $.msgstr is rw;
    # msgctxt
    has Str $.msgctxt is rw;
    # #:
    has Str $.reference is rw;
    # #.
    has Str $.extracted is rw;
    # #
    has Str $.comment is rw;
    # #,
    has Str $.format-style is rw;
    # #|
    has Str $.fuzzy-msgid is rw;
    has Str $.fuzzy-msgctxt is rw;

    # Accessors
    method msgid-quoted { po-quote($!msgid) }
    method msgstr-quoted {
        $!msgstr ~~ Str ??
        po-quote($!msgstr) !!
        $!msgstr.map({ po-quote($_) })
    }

    method Str() {
        my $result;

        $result ~= "# $!comment\n" if $!comment;
        $result ~= "#. $!extracted\n" if $!extracted;
        $result ~= "#: $!reference\n" if $!reference;
        $result ~= "#, $!format-style\n" if $!format-style;
        $result ~= "#| msgctxt $!fuzzy-msgctxt\n" if $!fuzzy-msgctxt;
        $result ~= "#| msgid $!fuzzy-msgid\n" if $!fuzzy-msgid;
        $result ~= "msgctxt $!msgctxt\n" if $!msgctxt;
        $result ~= "msgid \"{self.msgid-quoted}\"\n";
        if $!msgid-plural {
            $result ~= "msgid_plural \"{po-quote($!msgid-plural)}\"\n";
            for @$!msgstr.kv -> $index, $value {
                $result ~= "msgstr[$index] \"{po-quote($value)}\"\n";
            }
        } else {
            $result ~= "msgstr \"{po-quote($!msgstr)}\"";
        }

        $result;
    }

    method parse(Str $input) {
        my $m = POFile::Parser.parse($input, :rule<PO-rule-or-error>, actions => PO::Actions);
        my %args = $m.made;
        %args{'msgid'} = po-unquote(%args{'msgid'});
        if %args{'msgid-plural'}.defined {
            %args{'msgid-plural'} = po-unquote(%args{'msgid-plural'});
        }
        my $msgstr = %args{'msgstr'};
        $msgstr = $msgstr ~~ Str ?? po-unquote($msgstr) !! $msgstr.map({ po-unquote($_) }).Array;
        %args{'msgstr'} = $msgstr;
        self.bless(|%args);
    }
}

class POFile does Associative does Positional {
    has @!items;
    has %!entries;
    has @.obsolete-messages;

    submethod BUILD(:@!items, :%!entries, :@!obsolete-messages) {}

    method list { @!items }
    method hash { %!entries }

    # Associative && Positional
    method of() { POFile::Entry }
    # Associative
    method AT-KEY($key) { %!entries{$key} }
    method EXISTS-KEY($key) { %!entries{$key}:exists }
    # Positional
    method AT-POS($index) { @!items[$index] }
    method EXISTS-POS($index) { 0 < $index < @!items.size }

    method DELETE-POS($index) {
        if 0 < $index < @!items.elems {
            # Index starts from 1
            my $item = @!items.splice($index - 1, 1, ());
            %!entries{$item[0].msgid}:delete;
        } else {
            die POFile::IncorrectIndex.new(:$index, max => @!items.elems + 1);
        }
    }
    method DELETE-KEY($key) {
        with %!entries{$key} {
            @!items .= grep({ not $_.msgid eq $key }); # order is preserved
            %!entries{$key}:delete;
        } else {
            die POFile::IncorrectKey.new(:$key);
        }
    }

    method push(POFile::Entry $entry) {
        @!items.push($entry);
        %!entries{$entry.msgid} = $entry;
    }

    method elems() { @!items.elems }

    method Str() {
        if @!obsolete-messages.elems > 0 {
            my $obsolete = "\n#~ " ~ @!obsolete-messages.join("\n#~ ");
            @!items>>.Str.join("\n\n") ~ $obsolete;
        } else {
            @!items>>.Str.join("\n\n") ~ "\n";
        }
    }

    method !create($text) {
        my $result = $text.made;
        my @obsolete-messages = $result[1];
        my (@items, %entries);
        for $result[0] -> $rule {
            @items.push: $rule;
            %entries{$rule.msgid} = $rule;
        }
        self.bless(:@obsolete-messages, :@items, :%entries);
    }

    method parse(Str $input) {
        my $m = POFile::Parser.parse($input, actions => PO::Actions);
        self!create($m);
    }

    method load(Str() $path) {
        my $m = POFile::Parser.parsefile($path, actions => PO::Actions);
        self!create($m);
    }

    method save(Str() $path) {
        spurt $path, self.Str;
    }
}


sub po-quote(Str $input) is export(:quoting) {
    my $output = '';
    my @chars = $input.comb;
    my $size = @chars.elems;
    for @chars.kv -> $index, $char {
        unless $char eq '\\'|'"' {
            $output ~= $char; next;
        }
        if $char eq '"' {
            $output ~= '\\"';
        } else {
            if $index + 1 < $size { # At least one more character in buffer
                if @chars[$index + 1] eq 't'|'n' {
                    $output ~= '\\';
                } else {
                    $output ~= '\\\\';
                }
            } else { # Last character, so must be plain slash
                $output ~= '\\\\';
            }
        }
    }
    $output;
}

sub po-unquote(Str $input) is export(:quoting) {
    $input.trans(['\\\\', '\\"'] => ['\\', '"']);
}

=begin pod

=head1 NAME

POFile - manipulating data in gettext PO files

=head1 SYNOPSIS

=begin code :lang<raku>

use POFile;
my $po = POFile.load('foo.po');

say $po.obsolete-messages; # list of obsolete messages
say $po[0]; # POFile::Entry object at 0 index
say $po{'Splash text'}; # POFile::Entry object with msgid C<Splash textC<
for @$po -> $item {
    say $item.reference; # 'finddialog.cpp:38'
    say $item.msgstr; # msgstr value
    $item.msgstr = update($item.msgstr); # Do some update
}
$po.save('foo-updated.po');

=end code

=head1 DESCRIPTION

The C<.po> file as a whole is represented by the C<POFile> class,
which holds a C<POFile::Entry> object per entry in the PO file.

=head2 POFile::Entry

The C<POFile::Entry> class represents a single record in PO file,
and has its fields as attributes: C<msgid>, C<msgid-plural>,
C<msgstr>, C<msgctxt>, C<reference> (reference comment),
C<extracted> (extracted comment), C<comment> (translator comment),
C<format-style>, C<fuzzy-msgid>, C<fuzzy-msgctxt>. All these
attributes are set read/write.

You can create a single C<POFile::Entry> object from a C<Str>
using the C<POFile::Entry.parse($str)> method.

The C<msgid> and C<msgstr> accessors always provided unquoted
values; the methods C<msgid-quoted> and C<msgstr-quoted> are present
to provide access to the quoted messages.

The value of C<msgstr> attribute might be either C<Str> or C<Array>,
and is based on value of C<msgid-plural> attribute:

=begin code :lang<raku>

with $po.msgid-plural {
    say $po.msgid; # Singular form
    say $_; # Plural form
    for $po.msgstr -> $form {
        say $form; # Every plural form of end language
    }
}

=end code

You can serialize an entry with C<Str> method or its C<~> shortcut:

=begin code :lang<raku>

my $po-entry = $po[1]; # Get second entry
say ~$po-entry;    # Serialized 1
say $po-entry.Str; # Serialized 2

=end code

Note that B<no line wrapping> is done by the module.

=head2 POFile

C<POFile> provides access to C<POFile::Entry> objects using either
index (position in original file) or key (msgid value).

It must be noted that this module provides hash-like access by msgid,
which might B<not> be unique. Please consider that I<only array access>
is stable in this case. Use hash access you know I<for sure> there
are no items with the same C<msgid>, yet different C<msgctxt>.

The C<POFile> object also contains all obsolete messages, which cani
be accessed using C<obsolete-messages> attribute.

You can create from scratch a new C<POFile> object and populate it with
entries, as well as delete entries by id or by key:

=begin code :lang<raku>

my $po = POFile.new;
@$po.push(POFile::Entry.parse(...));
@$po.push(POFile::Entry.parse(...));
$po[0]:delete;
$po{'my msgid'}:delete;

=end code

As well as C<POFile::Entry>, you can serialize a C<POFile> object
calling C<Str> method on it.

=head2 Escaping

Additionally, two routines are available to escape and unescape
strings accordingly to rules described for PO format.

=begin code :lang<raku>

use POFile :quoting;

say po-unquote(｢\t\"\\\n｣); # ｢\t"\\n｣      <- unquoting
say po-quote(｢\t"\\n\｣);    # ｢\t\"\\\n\\｣  <- quoting

=end code

=head1 AUTHORS

=item Alexander Kiryuhin
=item Jonathan Worthington

Source can be located at: https://github.com/raku-community-modules/POFile .
Comments and Pull Requests are welcome.

=head1 COPYRIGHT AND LICENSE

Copyright 2018 - 2020 Edument AB

Copyright 2024 The Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

# vim: expandtab shiftwidth=4
