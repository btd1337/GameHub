using Gee;

using GameHub.Utils;

namespace GameHub.Data
{
	public abstract class Game: Object
	{
		public GameSource source { get; protected set; }

		public string id { get; protected set; }
		public string name { get; protected set; }
		public string description { get; protected set; }

		public string icon { get; protected set; }
		public string image { get; protected set; }

		public string? info { get; protected set; }
		public string? info_detailed { get; protected set; }

		public ArrayList<Platform> platforms { get; protected set; default = new ArrayList<Platform>(); }
		public virtual bool is_supported(Platform? platform=null)
		{
			if(platform == null) platform = CurrentPlatform;
			return platform in platforms;
		}

		public ArrayList<GamesDB.Tables.Tags.Tag> tags { get; protected set; default = new ArrayList<GamesDB.Tables.Tags.Tag>(GamesDB.Tables.Tags.Tag.is_equal); }
		public bool has_tag(GamesDB.Tables.Tags.Tag tag)
		{
			return has_tag_id(tag.id);
		}
		public bool has_tag_id(string tag)
		{
			foreach(var t in tags)
			{
				if(t.id == tag) return true;
			}
			return false;
		}
		public void add_tag(GamesDB.Tables.Tags.Tag tag)
		{
			if(!tags.contains(tag))
			{
				tags.add(tag);
			}
			GamesDB.get_instance().add_game(this);
			status_change(_status);
			tags_update();
		}
		public void remove_tag(GamesDB.Tables.Tags.Tag tag)
		{
			if(tags.contains(tag))
			{
				tags.remove(tag);
			}
			GamesDB.get_instance().add_game(this);
			status_change(_status);
			tags_update();
		}
		public void toggle_tag(GamesDB.Tables.Tags.Tag tag)
		{
			if(tags.contains(tag))
			{
				remove_tag(tag);
			}
			else
			{
				add_tag(tag);
			}
		}

		public bool is_installable { get; protected set; default = false; }

		public File executable { get; protected set; }
		public File install_dir { get; protected set; }
		public string? store_page { get; protected set; default = null; }

		public abstract async void install();
		public abstract async void run();
		public abstract async void uninstall();

		public virtual async void update_game_info(){}

		protected Game.Status _status = new Game.Status();
		public signal void status_change(Game.Status status);
		public signal void tags_update();

		public Game.Status status
		{
			get { return _status; }
			set { _status = value; status_change(_status); }
		}

		public virtual string installation_dir_name
		{
			owned get
			{
				return name.escape().replace(" ", "_").replace(":", "");
			}
		}

		public static bool is_equal(Game first, Game second)
		{
			return first == second || (first.source == second.source && first.id == second.id);
		}

		public static uint hash(Game game)
		{
			return str_hash(@"$(game.source.name)/$(game.id)");
		}

		public abstract class Installer
		{
			public class Part: Object
			{
				public string id     { get; construct; }
				public string url    { get; construct; }
				public int64  size   { get; construct; }
				public File   remote { get; construct; }
				public File   local  { get; construct; }
				public Part(string id, string url, int64 size, File remote, File local)
				{
					Object(id: id, url: url, size: size, remote: remote, local: local);
				}
			}

			public string   id           { get; protected set; }
			public Platform platform     { get; protected set; default = CurrentPlatform; }
			public ArrayList<Part> parts { get; protected set; default = new ArrayList<Part>(); }
			public int64    full_size    { get; protected set; default = 0; }

			public virtual string  name  { get { return id; } }

			public async void install(Game game)
			{
				try
				{
					game.status = new Game.Status(Game.State.DOWNLOADING, null);

					var files = new ArrayList<File>();

					uint p = 1;
					foreach(var part in parts)
					{
						var ds_id = Downloader.get_instance().download_started.connect(dl => {
							if(dl.remote != part.remote) return;
							game.status = new Game.Status(Game.State.DOWNLOADING, dl);
							dl.status_change.connect(s => {
								game.status_change(game.status);
							});
						});

						var partDesc = "";

						if(parts.size > 1)
						{
							partDesc = _("Part %u of %u: ").printf(p, parts.size);
						}

						var info = new Downloader.DownloadInfo(game.name, partDesc + part.id, game.icon, null, null, game.source.icon);
						files.add(yield Downloader.download(part.remote, part.local, info));
						Downloader.get_instance().disconnect(ds_id);

						p++;
					}

					uint f = 0;
					bool gog_windows_installer = false;
					foreach(var file in files)
					{
						var path = file.get_path();
						Utils.run({"chmod", "+x", path});

						FSUtils.mkdir(game.install_dir.get_path());

						var type = yield guess_type(file, f > 0);

						string[]? cmd = null;

						switch(type)
						{
							case InstallerType.EXECUTABLE:
								cmd = {path, "--", "--i-agree-to-all-licenses",
										"--noreadme", "--nooptions", "--noprompt",
										"--destination", game.install_dir.get_path().replace("'", "\\'")}; // probably mojosetup
								break;

							case InstallerType.ARCHIVE:
								cmd = {"file-roller", path, "-e", game.install_dir.get_path()}; // extract with file-roller
								break;

							case InstallerType.WINDOWS_EXECUTABLE:
								cmd = {"innoextract", "-e", "-m", "-d", game.install_dir.get_path(), (game is Sources.GOG.GOGGame) ? "--gog" : "", path}; // use innoextract
								break;

							case InstallerType.GOG_PART:
								cmd = null; // do nothing, already extracted
								break;

							default:
								cmd = {"xdg-open", path}; // unknown type, just open
								break;
						}

						game.status = new Game.Status(Game.State.INSTALLING);

						if(cmd != null)
						{
							yield Utils.run_async(cmd, null, false, true);
						}
						if(type == InstallerType.WINDOWS_EXECUTABLE)
						{
							gog_windows_installer = true;
						}
						f++;
					}

					try
					{
						string? dirname = null;
						FileInfo? finfo = null;
						var enumerator = yield game.install_dir.enumerate_children_async("standard::*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
						while((finfo = enumerator.next_file()) != null)
						{
							if(gog_windows_installer)
							{
								dirname = "app";
								if(finfo.get_name() != "app")
								{
									FSUtils.rm(game.install_dir.get_path(), finfo.get_name(), "-rf");
								}
								continue;
							}
							if(dirname == null)
							{
								dirname = finfo.get_name();
							}
							else
							{
								dirname = null;
							}
						}

						if(dirname != null)
						{
							Utils.run({"bash", "-c", "mv " + dirname + "/* " + dirname + "/.* ."}, game.install_dir.get_path());
							FSUtils.rm(game.install_dir.get_path(), dirname, "-rf");
						}
					}
					catch(Error e){}

					Utils.run({"chmod", "-R", "+x", game.install_dir.get_path()});
				}
				catch(IOError.CANCELLED e){}
				catch(Error e)
				{
					warning(e.message);
				}
				game.status = new Game.Status(game.executable.query_exists() ? Game.State.INSTALLED : Game.State.UNINSTALLED);
			}

			private static async InstallerType guess_type(File file, bool part=false)
			{
				var type = InstallerType.UNKNOWN;

				try
				{
					var finfo = yield file.query_info_async(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
					var mime = finfo.get_content_type();
					type = InstallerType.from_mime(mime);

					if(type != InstallerType.UNKNOWN) return type;

					var info = yield Utils.run_thread({"file", "-bi", file.get_path()});
					if(info != null && info.length > 0)
					{
						mime = info.split(";")[0];
						if(mime != null && mime.length > 0)
						{
							type = InstallerType.from_mime(mime);
						}
					}

					if(type != InstallerType.UNKNOWN) return type;

					string[] gog_part_ext = {"bin"};
					string[] exe_ext = {"sh", "elf", "bin", "run"};
					string[] win_exe_ext = {"exe"};
					string[] arc_ext = {"zip", "tar", "cpio", "bz2", "gz", "lz", "lzma", "7z", "rar"};

					if(part)
					{
						foreach(var ext in gog_part_ext)
						{
							if(file.get_basename().has_suffix(@".$(ext)")) return InstallerType.GOG_PART;
						}
					}

					foreach(var ext in exe_ext)
					{
						if(file.get_basename().has_suffix(@".$(ext)")) return InstallerType.EXECUTABLE;
					}
					foreach(var ext in win_exe_ext)
					{
						if(file.get_basename().has_suffix(@".$(ext)")) return InstallerType.EXECUTABLE;
					}
					foreach(var ext in arc_ext)
					{
						if(file.get_basename().has_suffix(@".$(ext)")) return InstallerType.ARCHIVE;
					}
				}
				catch(Error e){}

				return type;
			}

			private enum InstallerType
			{
				UNKNOWN, EXECUTABLE, WINDOWS_EXECUTABLE, GOG_PART, ARCHIVE;

				public static InstallerType from_mime(string type)
				{
					switch(type.strip())
					{
						case "application/x-executable":
						case "application/x-elf":
						case "application/x-sh":
						case "application/x-shellscript":
							return InstallerType.EXECUTABLE;

						case "application/x-dosexec":
						case "application/x-ms-dos-executable":
						case "application/dos-exe":
						case "application/exe":
						case "application/msdos-windows":
						case "application/x-exe":
						case "application/x-msdownload":
						case "application/x-winexe":
							return InstallerType.WINDOWS_EXECUTABLE;

						case "application/octet-stream":
							return InstallerType.GOG_PART;

						case "application/zip":
						case "application/x-tar":
						case "application/x-gtar":
						case "application/x-cpio":
						case "application/x-bzip2":
						case "application/gzip":
						case "application/x-lzip":
						case "application/x-lzma":
						case "application/x-7z-compressed":
						case "application/x-rar-compressed":
						case "application/x-compressed-tar":
							return InstallerType.ARCHIVE;
					}
					return InstallerType.UNKNOWN;
				}
			}
		}

		public class Status
		{
			public Game.State state;

			public Downloader.Download? download;

			public Status(Game.State state=Game.State.UNINSTALLED, Downloader.Download? download=null)
			{
				this.state = state;
				this.download = download;
			}

			public string description
			{
				owned get
				{
					switch(state)
					{
						case Game.State.INSTALLED: return _("Installed");
						case Game.State.INSTALLING: return _("Installing");
						case Game.State.DOWNLOADING: return download != null ? download.status.description : _("Download started");
					}
					return _("Not installed");
				}
			}

			public string header
			{
				owned get
				{
					switch(state)
					{
						case Game.State.INSTALLED: return _("Installed:");
						case Game.State.INSTALLING: return _("Installing:");
						case Game.State.DOWNLOADING: return _("Downloading:");
					}
					return _("Not installed:");
				}
			}
		}

		public enum State
		{
			UNINSTALLED, INSTALLED, DOWNLOADING, INSTALLING;
		}
	}

	public enum Platform
	{
		LINUX, WINDOWS, MACOS;

		public string id()
		{
			switch(this)
			{
				case Platform.LINUX: return "linux";
				case Platform.WINDOWS: return "windows";
				case Platform.MACOS: return "mac";
			}
			assert_not_reached();
		}

		public string name()
		{
			switch(this)
			{
				case Platform.LINUX: return "Linux";
				case Platform.WINDOWS: return "Windows";
				case Platform.MACOS: return "macOS";
			}
			assert_not_reached();
		}

		public string icon()
		{
			switch(this)
			{
				case Platform.LINUX: return "platform-linux-symbolic";
				case Platform.WINDOWS: return "platform-windows-symbolic";
				case Platform.MACOS: return "platform-macos-symbolic";
			}
			assert_not_reached();
		}
	}
	public static Platform[] Platforms;
	public static Platform CurrentPlatform;
}
