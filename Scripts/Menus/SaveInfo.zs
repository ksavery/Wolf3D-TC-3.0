// What a save is. The engine's comment only knows the shared "Level" map, and
// nothing outside a save can read inside one, so saves carry this in their title
// after SEPARATOR.
//
// The engine's autosaves name themselves and share one rotation across games.
// They stay for respawning but aren't listed: each game instead keeps its own
// few, made as ordinary saves a moment into a level.
class SaveInfo : StaticEventHandler
{
	const SEPARATOR = "\x1F";
	const KEEPAUTOSAVES = 4; // For each game
	const AUTOSAVEDELAY = 35; // Tics into a level, clear of the engine's own autosave

	ui Map<String, String> known; // By file name
	int autosaves; // Levels entered
	ui int autosaveswritten;

	static clearscope SaveInfo Get()
	{
		return SaveInfo(StaticEventHandler.Find("SaveInfo"));
	}

	// game|map|level tics|total tics
	static clearscope String Current()
	{
		MapHandler handler = MapHandler.Get();
		ParsedMap map = handler ? handler.curmap : null;

		String mapname = level.LevelName;
		if (map)
		{
			int len = 0;
			while (len < int(map.mapname.Length()) && map.mapname.ByteAt(len) >= 0x20) { len++; }
			mapname = ZScriptTools.Trim(map.mapname.Left(len));
		}
		mapname.Replace("|", "/");

		return String.Format("%s|%s|%i|%i", handler ? handler.gametitle : "", mapname, level.maptime, level.totaltime);
	}

	static void RequestAutosave()
	{
		let this = SaveInfo.Get();
		if (this) { this.autosaves++; }
	}

	override void UiTick()
	{
		if (gamestate != GS_LEVEL || Menu.GetCurrentMenu()) { return; }

		// A quicksave reuses the title it's saving over
		SavegameManager manager = SavegameManager.GetManager();
		if (manager.quickSaveSlot && !(gametic % GameTicRate))
		{
			// (Only one of these: it's a placeholder while the slot is being picked)
			for (int s = 0; s < manager.SavegameCount(); s++)
			{
				SaveGameNode node = manager.GetSavegame(s);
				if (node == manager.quickSaveSlot) { node.SaveTitle = Tagged(node.SaveTitle); }
			}
		}

		if (autosaveswritten == autosaves || level.maptime < AUTOSAVEDELAY) { return; }
		autosaveswritten = autosaves;

		if (multiplayer || disableautosave >= 2) { return; }

		MapHandler handler = MapHandler.Get();
		if (!handler || !handler.curmap) { return; }

		manager.ReadSaveStrings();
		ReadTitles(manager);

		// The oldest of this game's, once it has them all
		int count, oldest = -1;
		String oldesttitle;
		for (int s = 0; s < manager.SavegameCount(); s++)
		{
			SaveGameNode node = manager.GetSavegame(s);
			if (!node || !IsAutosave(node) || !known.CheckKey(node.Filename) || !(GameOf(known.Get(node.Filename)) ~== handler.gametitle)) { continue; }

			count++;
			if (oldest < 0 || node.SaveTitle < oldesttitle)
			{
				oldest = s;
				oldesttitle = node.SaveTitle;
			}
		}

		String title = Tagged("Autosave " .. SystemTime.Format("%Y-%m-%d %H:%M:%S", SystemTime.Now()));
		// Row 0 of the list is always the new save, and that needs to exist
		manager.InsertNewSaveNode();
		manager.DoSave(count >= KEEPAUTOSAVES ? oldest + 1 : 0, title);
		manager.RemoveNewSaveNode();
	}

	// With this moment's details in place of any it has
	static clearscope String Tagged(String title)
	{
		int at = title.IndexOf(SEPARATOR);

		return (at < 0 ? title : title.Left(at)) .. SEPARATOR .. Current();
	}

	static ui bool IsAutosave(SaveGameNode node)
	{
		return node.SaveTitle.Left(9) == "Autosave ";
	}

	// The engine's own: auto00.zds and so on
	static ui bool IsEngineAutosave(SaveGameNode node)
	{
		String file = node.Filename;
		file = file.Mid(file.RightIndexOf("/") + 1);

		return file.Left(4) ~== "auto";
	}

	// Move each save's details out of its title, where the list would draw them
	ui void ReadTitles(SavegameManager manager)
	{
		for (int s = 0; s < manager.SavegameCount(); s++)
		{
			SaveGameNode node = manager.GetSavegame(s);
			if (!node || !node.Filename.length()) { continue; }

			int at = node.SaveTitle.IndexOf(SEPARATOR);
			if (at < 0) { continue; }

			known.Insert(node.Filename, node.SaveTitle.Mid(at + 1));
			node.SaveTitle = node.SaveTitle.Left(at);
		}
	}

	static clearscope String FormatTime(int tics)
	{
		int seconds = tics / GameTicRate;

		return String.Format("%02i:%02i:%02i", seconds / 3600, (seconds / 60) % 60, seconds % 60);
	}

	static clearscope String GameOf(String info)
	{
		int at = info.IndexOf("|");

		return at < 0 ? "" : info.Left(at);
	}

	static clearscope String Describe(String info)
	{
		Array<String> parts;
		info.Split(parts, "|");
		if (parts.Size() < 4) { return ""; }

		String text = parts[1] .. "\n";
		if (parts[0].length()) { text = parts[0] .. "\n" .. text; }

		return text .. "Level time: " .. FormatTime(parts[2].ToInt()) .. "\nTotal time: " .. FormatTime(parts[3].ToInt());
	}
}

mixin class SaveListInfo
{
	Array<int> rows; // The saves listed: all at the title, the running game's in a level
	int toprow;
	bool filtering;

	void ReadSaveInfo()
	{
		let store = SaveInfo.Get();
		if (store) { store.ReadTitles(manager); }

		ListSaves();
	}

	// Saves from before these details can't be told apart, so they stay listed
	void ListSaves()
	{
		MapHandler handler = MapHandler.Get();
		filtering = gamestate == GS_LEVEL && handler && handler.curmap;

		let store = SaveInfo.Get();
		rows.Clear();
		for (int s = 0; s < manager.SavegameCount(); s++)
		{
			SaveGameNode node = manager.GetSavegame(s);
			if (!node || SaveInfo.IsEngineAutosave(node)) { continue; }

			String info = store && store.known.CheckKey(node.Filename) ? store.known.Get(node.Filename) : "";
			if (filtering && info.length() && !(SaveInfo.GameOf(info) ~== handler.gametitle)) { continue; }

			rows.Push(s);
		}

		// Whatever was selected may have just been filtered out or deleted
		if (Selected >= 0 && rows.Find(Selected) == rows.Size()) { SelectRow(rows.Size() ? 0 : -1); }
		toprow = clamp(toprow, 0, max(0, rows.Size() - listboxRows));
	}

	void SelectRow(int row)
	{
		Selected = row < 0 ? -1 : rows[row];

		if (row >= 0)
		{
			if (row < toprow) { toprow = row; }
			else if (row >= toprow + listboxRows) { toprow = row - listboxRows + 1; }
		}

		manager.UnloadSaveData();
		manager.ExtractSaveData(Selected);
		UpdateSaveComment();
	}

	bool MoveSelection(int mkey)
	{
		if (mkey != MKEY_Up && mkey != MKEY_Down && mkey != MKEY_PageUp && mkey != MKEY_PageDown) { return false; }
		if (rows.Size() < 2) { return true; }

		int row = rows.Find(Selected);
		bool none = row == rows.Size();

		if (mkey == MKEY_Up) { row = none ? toprow : (row + rows.Size() - 1) % rows.Size(); }
		else if (mkey == MKEY_Down) { row = none ? toprow : (row + 1) % rows.Size(); }
		else
		{
			int last = max(0, rows.Size() - listboxRows);
			if (mkey == MKEY_PageDown) { toprow = toprow >= last ? 0 : min(toprow + listboxRows, last); }
			else { toprow = toprow == 0 ? last : max(toprow - listboxRows, 0); }
			row = toprow;
		}

		SelectRow(row);

		return true;
	}

	// True if it was over the list
	bool ClickRow(int type, int x, int y)
	{
		if (x < listboxLeft || x >= listboxLeft + listboxWidth || y < listboxTop || y >= listboxTop + listboxHeight) { return false; }

		int row = toprow + (y - listboxTop) / rowHeight;
		if (row >= rows.Size())
		{
			Selected = -1;
			return true;
		}

		SelectRow(row);
		if (type == MOUSE_Release) { MenuEvent(MKEY_Enter, true); }

		return true;
	}

	bool ScrollRows(UIEvent ev)
	{
		if (ev.Type == UIEvent.Type_WheelUp) { toprow = max(toprow - 1, 0); return true; }
		if (ev.Type == UIEvent.Type_WheelDown) { toprow = min(toprow + 1, max(0, rows.Size() - listboxRows)); return true; }

		return false;
	}

	// The list is drawn here from rows, so the engine's own loop has nothing to do
	void HideEngineRows()
	{
		TopItem = manager.SavegameCount();
	}

	void DrawSaveRows()
	{
		if (gameaction == ga_loadgame || gameaction == ga_loadgamehidecon || gameaction == ga_savegame) { return; }

		double vwidth = screen.GetWidth() / FontScale;
		double vheight = screen.GetHeight() / FontScale;

		if (!rows.Size())
		{
			if (!manager.SavegameCount()) { return; }

			String text = StringTable.Localize("$MNU_NOFILES");
			int textlen = int(NewConsoleFont.StringWidth(text) * FontScale);
			screen.DrawText(NewConsoleFont, Font.CR_GOLD, (listboxLeft + (listboxWidth - textlen) / 2) / FontScale, (listboxTop + (listboxHeight - rowHeight) / 2) / FontScale, text, DTA_VirtualWidthF, vwidth, DTA_VirtualHeightF, vheight, DTA_KeepRatio, true);
			return;
		}

		let store = SaveInfo.Get();
		for (int i = 0; i < listboxRows && toprow + i < rows.Size(); i++)
		{
			int s = rows[toprow + i];
			SaveGameNode node = manager.GetSavegame(s);
			if (!node) { continue; }

			int colr = node.bOldVersion ? Font.CR_RED : node.bMissingWads ? Font.CR_YELLOW : s == Selected ? Font.CR_WHITE : Font.CR_TAN;
			double y = (listboxTop + rowHeight * i + FontScale) / FontScale;

			screen.SetClipRect(listboxLeft, listboxTop + rowHeight * i, listboxRight, listboxTop + rowHeight * (i + 1));

			if (s == Selected) { screen.Clear(listboxLeft, listboxTop + rowHeight * i, listboxRight, listboxTop + rowHeight * (i + 1), mEntering ? Color(255, 255, 0, 0) : Color(255, 0, 0, 255)); }

			if (s == Selected && mEntering)
			{
				String typed = mInput.GetText() .. NewConsoleFont.GetCursor();
				int length = int(NewConsoleFont.StringWidth(typed) * FontScale);
				int displacement = min(0, listboxWidth - 2 - length);
				screen.DrawText(NewConsoleFont, Font.CR_WHITE, (listboxLeft + 1 + displacement) / FontScale, y, typed, DTA_VirtualWidthF, vwidth, DTA_VirtualHeightF, vheight, DTA_KeepRatio, true);
			}
			else
			{
				screen.DrawText(NewConsoleFont, colr, (listboxLeft + 1) / FontScale, y, node.SaveTitle, DTA_VirtualWidthF, vwidth, DTA_VirtualHeightF, vheight, DTA_KeepRatio, true);

				// At the title all the games are listed, so say whose each one is
				String game = !filtering && store && store.known.CheckKey(node.Filename) ? SaveInfo.GameOf(store.known.Get(node.Filename)) : "";
				if (game.length())
				{
					int gamewidth = int(NewConsoleFont.StringWidth(game) * FontScale);
					screen.DrawText(NewConsoleFont, Font.CR_DARKGRAY, (listboxRight - 2 - gamewidth) / FontScale, y, game, DTA_VirtualWidthF, vwidth, DTA_VirtualHeightF, vheight, DTA_KeepRatio, true);
				}
			}

			screen.ClearClipRect();
		}
	}

	void ShowSaveInfo()
	{
		ListSaves();

		let store = SaveInfo.Get();
		if (!store || !rows.Size()) { return; }

		// Until a row is picked the comment is the first one's
		int shown = Selected < 0 ? rows[0] : Selected;
		if (shown >= manager.SavegameCount()) { return; }

		SaveGameNode node = manager.GetSavegame(shown);
		if (!node) { return; }

		String info;
		if (!node.Filename.length()) { info = SaveInfo.Current(); }
		else if (store.known.CheckKey(node.Filename)) { info = store.known.Get(node.Filename); }

		// The menu puts the engine's comment back whenever the selection moves
		String text = SaveInfo.Describe(info);
		if (text.length()) { BrokenSaveComment = NewConsoleFont.BreakLines(text, int(commentWidth / FontScale)); }
	}
}
