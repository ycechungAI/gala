//
//  Copyright (C) 2012 Tom Beckmann, Rico Tzschichholz
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Clutter;
using Meta;

namespace Gala {
    public class WindowSwitcher : Clutter.Actor {
        const int MIN_DELTA = 100;
        const float BACKGROUND_OPACITY = 155.0f;

        public WindowManager wm { get; construct; }

        Actor window_clones;
        List<unowned Actor> clone_sort_order;

        WindowActor? dock_window;
        int ui_scale_factor = 1;

        Actor background;

        uint modifier_mask;
        int64 last_switch = 0;
        bool closing = false;
        ModalProxy modal_proxy;

        public WindowSwitcher (WindowManager wm) {
            Object (wm: wm);
        }

        construct {
            ui_scale_factor = InternalUtils.get_ui_scaling_factor ();

            window_clones = new Actor ();
            window_clones.actor_removed.connect (window_removed);

            background = new Actor ();
            background.background_color = Color.get_static (StaticColor.BLACK);
            update_background ();

            add_child (background);
            add_child (window_clones);

#if HAS_MUTTER330
            Meta.MonitorManager.@get ().monitors_changed.connect (update_actors);
#else
            wm.get_screen ().monitors_changed.connect (update_actors);
#endif

            visible = false;
        }

        ~WindowSwitcher () {
#if HAS_MUTTER330
            Meta.MonitorManager.@get ().monitors_changed.disconnect (update_actors);
#else
            wm.get_screen ().monitors_changed.disconnect (update_actors);
#endif
        }

        void update_background () {
            int width = 0, height = 0;
#if HAS_MUTTER330
            wm.get_display ().get_size (out width, out height);
#else
            wm.get_screen ().get_size (out width, out height);
#endif

            background.set_size (width, height);
        }

        void update_actors () {
            update_background ();
        }

        void show_background () {
            background.save_easing_state ();
            background.set_easing_duration (250);
            background.set_easing_mode (AnimationMode.EASE_OUT_CUBIC);
            background.opacity = (uint)BACKGROUND_OPACITY;
            background.restore_easing_state ();
        }

        void hide_background () {
            background.save_easing_state ();
            background.set_easing_duration (250);
            background.set_easing_mode (AnimationMode.EASE_OUT_CUBIC);
            background.opacity = 0;
            background.restore_easing_state ();
        }

        void window_removed (Actor actor) {
            clone_sort_order.remove (actor);
        }

        public override bool key_press_event (Clutter.KeyEvent event) {
            if (event.keyval == Clutter.Key.Escape) {
                close (event.time);
                return true;
            }

            return false;
        }

        public override bool key_release_event (Clutter.KeyEvent event) {
            if ((get_current_modifiers () & modifier_mask) == 0)
                close (event.time);

            return true;
        }

        public override void key_focus_out () {
#if HAS_MUTTER330
            close (wm.get_display ().get_current_time ());
#else
            close (wm.get_screen ().get_display ().get_current_time ());
#endif
        }

        [CCode (instance_pos = -1)]
#if HAS_MUTTER330
        public void handle_switch_windows (Display display, Window? window, Clutter.KeyEvent event,
            KeyBinding binding) {
#else
        public void handle_switch_windows (Display display, Screen screen, Window? window,
            Clutter.KeyEvent event, KeyBinding binding) {
#endif
            var now = get_monotonic_time () / 1000;
            if (now - last_switch < MIN_DELTA)
                return;

            // if we were still closing while the next invocation comes in, we need to cleanup
            // things right away
            if (visible && closing) {
                close_cleanup ();
            }

            last_switch = now;

#if HAS_MUTTER330
            var workspace = display.get_workspace_manager ().get_active_workspace ();
#else
            var workspace = screen.get_active_workspace ();
#endif
            var binding_name = binding.get_name ();
            var backward = binding_name.has_suffix ("-backward");

            // FIXME for unknown reasons, switch-applications-backward won't be emitted, so we
            //       test manually if shift is held down
            if (binding_name == "switch-applications")
                backward = ((get_current_modifiers () & ModifierType.SHIFT_MASK) != 0);

            if (visible && !closing) {
                return;
            }

            if (!collect_windows (workspace))
                return;

            set_primary_modifier (binding.get_mask ());

            visible = true;
            closing = false;
            modal_proxy = wm.push_modal ();
            modal_proxy.keybinding_filter = (binding) => {
                // if it's not built-in, we can block it right away
                if (!binding.is_builtin ())
                    return true;

                // otherwise we determine by name if it's meant for us
                var name = binding.get_name ();

                return !(name == "switch-applications" || name == "switch-applications-backward"
                    || name == "switch-windows" || name == "switch-windows-backward");
            };

            show_background ();

            grab_key_focus ();

#if HAS_MUTTER330
            if ((get_current_modifiers () & modifier_mask) == 0)
                close (wm.get_display ().get_current_time ());
#else
            if ((get_current_modifiers () & modifier_mask) == 0)
                close (wm.get_screen ().get_display ().get_current_time ());
#endif
        }

        void close_cleanup () {
#if HAS_MUTTER330
            var display = wm.get_display ();
            var workspace = display.get_workspace_manager ().get_active_workspace ();
#else
            var screen = wm.get_screen ();
            var workspace = screen.get_active_workspace ();
#endif

            dock_window = null;
            visible = false;
            closing = false;

            window_clones.destroy_all_children ();

            // need to go through all the windows because of hidden dialogs
#if HAS_MUTTER330
            unowned GLib.List<Meta.WindowActor> window_actors = display.get_window_actors ();
#else
            unowned GLib.List<Meta.WindowActor> window_actors = screen.get_window_actors ();
#endif
            foreach (unowned Meta.WindowActor actor in window_actors) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.get_workspace () == workspace
                    && window.showing_on_its_workspace ())
                    actor.show ();
            }
        }

        void close (uint time) {
            if (closing)
                return;

            closing = true;
            last_switch = 0;

            foreach (var actor in clone_sort_order) {
                unowned SafeWindowClone clone = (SafeWindowClone) actor;

                // reset order
                window_clones.set_child_below_sibling (clone, null);

                if (!clone.window.minimized) {
                    clone.save_easing_state ();
                    clone.set_easing_duration (150);
                    clone.set_easing_mode (AnimationMode.EASE_OUT_CUBIC);
                    clone.z_position = 0;
                    clone.opacity = 255;
                    clone.restore_easing_state ();
                }
            }

            wm.pop_modal (modal_proxy);

            if (dock_window != null) {
                dock_window.opacity = 0;
                dock_window.show ();
                dock_window.save_easing_state ();
                dock_window.set_easing_mode (AnimationMode.LINEAR);
                dock_window.set_easing_duration (250);
                dock_window.opacity = 255;
                dock_window.restore_easing_state ();
            }

            hide_background ();

            close_cleanup ();
        }

        void add_window (Window window) {
            var actor = window.get_compositor_private () as WindowActor;
            if (actor == null)
                return;

            actor.hide ();

            var clone = new SafeWindowClone (window, true) {
                x = actor.x,
                y = actor.y
            };

            window_clones.add_child (clone);
        }

        /**
         * Adds the suitable windows on the given workspace to the switcher
         *
         * @return whether the switcher should actually be started or if there are
         *         not enough windows
         */
        bool collect_windows (Workspace workspace) {
#if HAS_MUTTER330
            var display = workspace.get_display ();
#else
            var screen = workspace.get_screen ();
            var display = screen.get_display ();
#endif

            var windows = display.get_tab_list (TabList.NORMAL, workspace);
            var current = display.get_tab_current (TabList.NORMAL, workspace);

            if (windows.length () < 1)
                return false;

            if (windows.length () == 1) {
                var window = windows.data;
                if (window.minimized)
                    window.unminimize ();
                else
#if HAS_MUTTER330
                    Utils.bell (display);
#else
                    Utils.bell (screen);
#endif

                window.activate (display.get_current_time ());

                return false;
            }

            foreach (var window in windows) {
                add_window (window);
            }

            clone_sort_order = window_clones.get_children ().copy ();

            // hide the others
#if HAS_MUTTER330
            unowned GLib.List<Meta.WindowActor> window_actors = display.get_window_actors ();
#else
            unowned GLib.List<Meta.WindowActor> window_actors = screen.get_window_actors ();
#endif
            foreach (unowned Meta.WindowActor actor in window_actors) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                var type = window.window_type;

                if (type != WindowType.DOCK
                    && type != WindowType.DESKTOP
                    && type != WindowType.NOTIFICATION)
                    actor.hide ();
                var behavior_settings = new GLib.Settings (Config.SCHEMA + ".behavior");
                if (window.title in behavior_settings.get_strv ("dock-names")
                    && type == WindowType.DOCK) {
                    dock_window = actor;
                    dock_window.hide ();
                }
            }

            return true;
        }

        /**
         * copied from gnome-shell, finds the primary modifier in the mask and saves it
         * to our modifier_mask field
         *
         * @param mask The modifier mask to extract the primary one from
         */
        void set_primary_modifier (uint mask) {
            if (mask == 0)
                modifier_mask = 0;
            else {
                modifier_mask = 1;
                while (mask > 1) {
                    mask >>= 1;
                    modifier_mask <<= 1;
                }
            }
        }

        Gdk.ModifierType get_current_modifiers () {
            Gdk.ModifierType modifiers;
            double[] axes = {};
            Gdk.Display.get_default ().get_default_seat ().get_pointer ()
                .get_state (Gdk.get_default_root_window (), axes, out modifiers);

            return modifiers;
        }
    }
}
