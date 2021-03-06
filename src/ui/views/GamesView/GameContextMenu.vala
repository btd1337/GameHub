using Gtk;
using Gdk;
using Granite;
using GameHub.Data;
using GameHub.Utils;
using GameHub.UI.Widgets;

namespace GameHub.UI.Views.GamesView
{
	public class GameContextMenu: Gtk.Menu
	{
		public Game game { get; construct; }

		public GameContextMenu(Game game)
		{
			Object(game: game);
		}

		construct
		{
			var run = new Gtk.MenuItem.with_label(_("Run"));
			run.activate.connect(() => game.run.begin());

			var install = new Gtk.MenuItem.with_label(_("Install"));
			install.activate.connect(() => game.install.begin());

			var details = new Gtk.MenuItem.with_label(_("Details"));
			details.activate.connect(() => new Dialogs.GameDetailsDialog(game).show_all());

			var favorite = new Gtk.CheckMenuItem.with_label(_("Favorite"));
			favorite.active = game.has_tag(GamesDB.Tables.Tags.BUILTIN_FAVORITES);
			favorite.toggled.connect(() => game.toggle_tag(GamesDB.Tables.Tags.BUILTIN_FAVORITES));

			var hidden = new Gtk.CheckMenuItem.with_label(_("Hidden"));
			hidden.active = game.has_tag(GamesDB.Tables.Tags.BUILTIN_HIDDEN);
			hidden.toggled.connect(() => game.toggle_tag(GamesDB.Tables.Tags.BUILTIN_HIDDEN));

			var manage_tags = new Gtk.MenuItem.with_label(_("Manage tags"));
			manage_tags.activate.connect(() => new Dialogs.GameTagsDialog.GameTagsDialog(game).show_all());

			if(game.status.state == Game.State.INSTALLED)
			{
				add(run);
			}
			else if(game.status.state == Game.State.UNINSTALLED)
			{
				add(install);
			}

			add(new Gtk.SeparatorMenuItem());

			add(details);

			add(new Gtk.SeparatorMenuItem());

			add(favorite);
			add(hidden);

			add(new Gtk.SeparatorMenuItem());

			add(manage_tags);

			show_all();
		}

		public void open(Widget widget, Event e)
		{
			#if GTK_3_22
			popup_at_pointer(e);
			#else
			popup(null, null, null, e.button, e.time);
			#endif
		}
	}
}