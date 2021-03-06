using Gtk;
using GLib;
using Gee;
using GameHub.Utils;
using GameHub.UI.Widgets;

using GameHub.Data;
using GameHub.Data.Sources.GOG;
using GameHub.Data.Sources.Humble;

namespace GameHub.UI.Dialogs
{
	public class GameInstallDialog: Dialog
	{
		private const int RESPONSE_IMPORT = 123;

		public signal void import();
		public signal void install(Game.Installer installer);
		public signal void cancelled();

		private Box content;
		private Label title_label;
		private Label subtitle_label;

		private ListBox installers_list;

		private bool is_finished = false;

		public GameInstallDialog(Game game, ArrayList<Game.Installer> installers)
		{
			Object(transient_for: Windows.MainWindow.instance, deletable: false, resizable: false, title: _("Install"));

			modal = true;

			content = new Box(Orientation.VERTICAL, 0);
			content.margin_start = content.margin_end = 8;

			var title_hbox = new Box(Orientation.HORIZONTAL, 16);

			var icon = new AutoSizeImage();
			icon.set_constraint(48, 48, 1);
			icon.set_size_request(48, 48);

			title_label = new Label(null);
			title_label.halign = Align.START;
			title_label.hexpand = true;
			title_label.get_style_context().add_class(Granite.STYLE_CLASS_H2_LABEL);

			subtitle_label = new Label(null);
			subtitle_label.halign = Align.START;
			subtitle_label.hexpand = true;

			var title_vbox = new Box(Orientation.VERTICAL, 0);

			title_vbox.add(title_label);

			title_hbox.add(icon);
			title_hbox.add(title_vbox);
			title_vbox.add(subtitle_label);

			content.add(title_hbox);

			title_label.label = game.name;
			Utils.load_image.begin(icon, game.icon, "icon");

			installers_list = new ListBox();
			installers_list.get_style_context().add_class("installers-list");
			installers_list.margin_start = 56;
			installers_list.margin_top = 8;
			installers_list.margin_bottom = 8;

			installers_list.set_sort_func((row1, row2) => {
				var item1 = row1 as InstallerRow;
				var item2 = row2 as InstallerRow;
				if(item1 != null && item2 != null)
				{
					var i1 = item1.installer;
					var i2 = item2.installer;

					if(i1.platform.id() == CurrentPlatform.id() && i2.platform.id() != CurrentPlatform.id()) return -1;
					if(i1.platform.id() != CurrentPlatform.id() && i2.platform.id() == CurrentPlatform.id()) return 1;

					return i1.name.collate(i2.name);
				}
				return 0;
			});

			var sys_langs = Intl.get_language_names();

			var compatible_installers = new ArrayList<Game.Installer>();

			foreach(var installer in installers)
			{
				if(installer.platform.id() != CurrentPlatform.id() && !Settings.UI.get_instance().show_unsupported_games) continue;

				compatible_installers.add(installer);
				var row = new InstallerRow(game, installer);
				installers_list.add(row);

				if(installer is GOGGame.Installer && (installer as GOGGame.Installer).lang in sys_langs)
				{
					installers_list.select_row(row);
				}
				else if(installers_list.get_selected_row() == null && installer.platform.id() == CurrentPlatform.id())
				{
					installers_list.select_row(row);
				}
			}

			if(compatible_installers.size > 1)
			{
				subtitle_label.label = _("Select game installer");
				content.add(installers_list);
			}
			else
			{
				subtitle_label.label = _("Installer size: %s").printf(format_size(compatible_installers[0].full_size));
			}

			destroy.connect(() => { if(!is_finished) cancelled(); });

			response.connect((source, response_id) => {
				switch(response_id)
				{
					case ResponseType.CANCEL:
						destroy();
						break;

					case GameInstallDialog.RESPONSE_IMPORT:
						is_finished = true;
						import();
						destroy();
						break;

					case ResponseType.ACCEPT:
						var installer = compatible_installers[0];
						if(compatible_installers.size > 1)
						{
							var row = installers_list.get_selected_row() as InstallerRow;
							installer = row.installer;
						}
						is_finished = true;
						install(installer);
						destroy();
						break;
				}
			});

			add_button(_("Cancel"), ResponseType.CANCEL);

			if(game is HumbleGame)
			{
				add_button(_("Import"), GameInstallDialog.RESPONSE_IMPORT);
			}

			var install_btn = add_button(_("Install"), ResponseType.ACCEPT);
			install_btn.get_style_context().add_class(STYLE_CLASS_SUGGESTED_ACTION);
			install_btn.grab_default();

			get_content_area().add(content);
			get_content_area().set_size_request(340, 96);
			show_all();
		}

		private class InstallerRow: ListBoxRow
		{
			public Game game;
			public Game.Installer installer;

			public InstallerRow(Game game, Game.Installer installer)
			{
				this.game = game;
				this.installer = installer;

				var box = new Box(Orientation.HORIZONTAL, 8);
				box.margin_start = box.margin_end = 8;
				box.margin_top = box.margin_bottom = 4;

				var icon = new Image.from_icon_name(game.source.icon, IconSize.BUTTON);

				icon.icon_name = installer.platform.icon();

				var name = new Label(installer.name);
				name.hexpand = true;
				name.halign = Align.START;

				var size = new Label(format_size(installer.full_size));
				size.halign = Align.END;

				box.add(icon);
				box.add(name);
				box.add(size);
				child = box;
			}
		}
	}
}
