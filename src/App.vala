/*
 * Copyright 2021 elementary, Inc. <https://elementary.io>
 * Copyright 2021 Corentin Noël <tintou@noel.tf>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Gala.App : GLib.Object {
    public string id {
        get {
            if (app_info != null) {
                return app_info.get_id ();
            } else {
                return window_id_string;
            }
        }
    }

    public GLib.DesktopAppInfo? app_info { get; construct; }

    public GLib.Icon icon {
        get {
            if (app_info != null) {
                return app_info.get_icon ();
            }

            if (fallback_icon == null) {
                fallback_icon = new GLib.ThemedIcon ("application-x-executable");
            }

            return fallback_icon;
        }
    }

    public string name {
        get {
            if (app_info != null) {
                return app_info.get_name ();
            } else {
                unowned string? name = null;
                var window = get_backing_window ();
                if (window != null) {
                    name = window.get_wm_class ();
                }

                return name ?? C_("program", "Unknown");
            }
        }
    }

    public string? description {
        get {
            if (app_info != null) {
                return app_info.get_description ();
            }

            return null;
        }
    }

    private GLib.SList<Meta.Window> windows = new GLib.SList<Meta.Window> ();
    private string? window_id_string = null;
    private GLib.Icon? fallback_icon = null;

    public App (GLib.DesktopAppInfo info) {
        Object (app_info: info);
    }

    public App.for_window (Meta.Window window) {
        window_id_string = "window:%u".printf (window.get_stable_sequence ());
        windows.prepend (window);
    }

    public unowned GLib.SList<Meta.Window> get_windows () {
        return windows;
    }

    private Meta.Window? get_backing_window () requires (app_info == null) {
        return windows.data;
    }
}
