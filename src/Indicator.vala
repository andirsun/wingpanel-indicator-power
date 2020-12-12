/*
 * Copyright (c) 2011-2015 elementary LLC. (https://elementary.io)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street - Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

public class Power.Indicator : Wingpanel.Indicator {
    private const string DBUS_PATH = "/org/gnome/SettingsDaemon/Power";
    private const string DBUS_NAME = "org.gnome.SettingsDaemon.Power";
    public bool is_in_session { get; construct; default = false; }

    private Widgets.DisplayWidget? display_widget = null;

    private Widgets.PopoverWidget? popover_widget = null;

    private Services.Device display_device;
    private Services.DBusInterfaces.PowerSettings iscreen;
    private bool notify_battery = false;

    public Indicator (bool is_in_session) {
        Object (
            code_name : Wingpanel.Indicator.POWER,
            is_in_session: is_in_session
        );

        init_bus.begin ();
        ((DBusProxy)iscreen).g_properties_changed.connect (update_tooltip);
    }

    private async void init_bus () {
        try {
            iscreen = Bus.get_proxy_sync (
                BusType.SESSION,
                DBUS_NAME,
                DBUS_PATH,
                DBusProxyFlags.GET_INVALIDATED_PROPERTIES
            );
        } catch (IOError e) {
            warning ("screen brightness error %s", e.message);
        }
    }

    public override Gtk.Widget get_display_widget () {
        if (display_widget == null) {
            display_widget = new Widgets.DisplayWidget ();

            var dm = Services.DeviceManager.get_default ();

            /* No need to display the indicator when the device is completely in AC mode */
            if (dm.has_battery || dm.backlight.present) {
                update_visibility ();
            }

            dm.notify["has-battery"].connect (update_visibility);
        }

        return display_widget;
    }

    public override Gtk.Widget? get_widget () {
        if (popover_widget == null) {
            popover_widget = new Widgets.PopoverWidget (is_in_session);
        }

        return popover_widget;
    }

    public override void opened () {
        Services.ProcessMonitor.Monitor.get_default ().update ();
    }

    public override void closed () {
        popover_widget.slim_down ();
    }

    private void update_visibility () {
        var dm = Services.DeviceManager.get_default ();

        bool should_be_visible = (dm.has_battery || dm.backlight.present);
        if (visible != should_be_visible) {
            /* NOTE: popover closes every time you set visibility, so change property only when needed */
            visible = should_be_visible;
        }

        if (visible) {
            if (dm.has_battery) {
                update_display_device ();
                if (!notify_battery) {
                    dm.notify["display-device"].connect (update_display_device);
                    notify_battery = true;
                }
            } else {
                show_backlight_data ();
                if (notify_battery) {
                    dm.notify["display-device"].disconnect (update_display_device);
                    notify_battery = false;
                }
            }
        }

        update_tooltip ();
    }

    private void update_display_device () {
       if (display_device != null) {
            display_device.properties_updated.disconnect (show_display_device_data);
        }

        display_device = Services.DeviceManager.get_default ().display_device;
        if (display_device != null) {
            show_display_device_data ();
            display_device.properties_updated.connect (show_display_device_data);
        }
    }

    private void show_display_device_data () {
        if (display_device != null && display_widget != null) {
            var icon_name = display_device.get_symbolic_icon_name_for_battery ();
            display_widget.icon_name = icon_name;

            /* Debug output for designers */
            debug ("Icon changed to \"%s\"", icon_name);

            var percent = (int)Math.round (display_device.percentage);

            if (percent <= 0) {
                display_widget.allow_percent = false;
            } else {
                display_widget.percentage = percent;
                display_widget.allow_percent = true;
            }

            update_tooltip ();
        }
    }

    private void show_backlight_data () {
        if (display_widget != null) {
            display_widget.icon_name = "display-brightness-symbolic";
            display_widget.allow_percent = false;
        }
    }

    private void update_tooltip () {
        var battery_percent = (int)Math.round (display_device.percentage);
        var brightness_percent = iscreen.brightness;

        display_widget.tooltip_markup = Granite.markup_contextual_tooltip (
            _("Middle-click to show battery percent in panel"),
            _("Battery: %i%% charged, Brightness: %i%%".printf (battery_percent, brightness_percent))
        );
    }
}

public Wingpanel.Indicator get_indicator (Module module, Wingpanel.IndicatorManager.ServerType server_type) {
    debug ("Activating Power Indicator");

    var indicator = new Power.Indicator (server_type == Wingpanel.IndicatorManager.ServerType.SESSION);

    return indicator;
}
