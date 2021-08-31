/*
 * Copyright 2021 elementary, Inc. <https://elementary.io>
 * Copyright 2021 Corentin Noël <tintou@noel.tf>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Gala.WindowTracker : GLib.Object {
    private Gala.App? focused_app = null;
    private GLib.HashTable<Meta.Window, Gala.App> window_to_app = new GLib.HashTable<Meta.Window, Gala.App> (GLib.direct_hash, GLib.direct_equal);
}
