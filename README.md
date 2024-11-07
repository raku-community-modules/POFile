[![Actions Status](https://github.com/raku-community-modules/POFile/actions/workflows/linux.yml/badge.svg)](https://github.com/raku-community-modules/POFile/actions) [![Actions Status](https://github.com/raku-community-modules/POFile/actions/workflows/macos.yml/badge.svg)](https://github.com/raku-community-modules/POFile/actions) [![Actions Status](https://github.com/raku-community-modules/POFile/actions/workflows/windows.yml/badge.svg)](https://github.com/raku-community-modules/POFile/actions)

NAME
====

POFile - manipulating data in gettext PO files

SYNOPSIS
========

```raku
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
```

DESCRIPTION
===========

The `.po` file as a whole is represented by the `POFile` class, which holds a `POFile::Entry` object per entry in the PO file.

POFile::Entry
-------------

The `POFile::Entry` class represents a single record in PO file, and has its fields as attributes: `msgid`, `msgid-plural`, `msgstr`, `msgctxt`, `reference` (reference comment), `extracted` (extracted comment), `comment` (translator comment), `format-style`, `fuzzy-msgid`, `fuzzy-msgctxt`. All these attributes are set read/write.

You can create a single `POFile::Entry` object from a `Str` using the `POFile::Entry.parse($str)` method.

The `msgid` and `msgstr` accessors always provided unquoted values; the methods `msgid-quoted` and `msgstr-quoted` are present to provide access to the quoted messages.

The value of `msgstr` attribute might be either `Str` or `Array`, and is based on value of `msgid-plural` attribute:

```raku
with $po.msgid-plural {
    say $po.msgid; # Singular form
    say $_; # Plural form
    for $po.msgstr -> $form {
        say $form; # Every plural form of end language
    }
}
```

You can serialize an entry with `Str` method or its `~` shortcut:

```raku
my $po-entry = $po[1]; # Get second entry
say ~$po-entry;    # Serialized 1
say $po-entry.Str; # Serialized 2
```

Note that **no line wrapping** is done by the module.

POFile
------

`POFile` provides access to `POFile::Entry` objects using either index (position in original file) or key (msgid value).

It must be noted that this module provides hash-like access by msgid, which might **not** be unique. Please consider that *only array access* is stable in this case. Use hash access you know *for sure* there are no items with the same `msgid`, yet different `msgctxt`.

The `POFile` object also contains all obsolete messages, which cani be accessed using `obsolete-messages` attribute.

You can create from scratch a new `POFile` object and populate it with entries, as well as delete entries by id or by key:

```raku
my $po = POFile.new;
@$po.push(POFile::Entry.parse(...));
@$po.push(POFile::Entry.parse(...));
$po[0]:delete;
$po{'my msgid'}:delete;
```

As well as `POFile::Entry`, you can serialize a `POFile` object calling `Str` method on it.

Escaping
--------

Additionally, two routines are available to escape and unescape strings accordingly to rules described for PO format.

```raku
use POFile :quoting;

say po-unquote(｢\t\"\\\n｣); # ｢\t"\\n｣      <- unquoting
say po-quote(｢\t"\\n\｣);    # ｢\t\"\\\n\\｣  <- quoting
```

AUTHORS
=======

  * Alexander Kiryuhin

  * Jonathan Worthington

Source can be located at: https://github.com/raku-community-modules/POFile . Comments and Pull Requests are welcome.

COPYRIGHT AND LICENSE
=====================

Copyright 2018 - 2020 Edument AB

Copyright 2024 The Raku Community

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

