{
  ids = [ "*" ];

  settings = {
    main = {
      capslock = "overload(capslock, esc)";
      esc = "capslock";
    };

    "capslock:C" = {
      # Arrows
      j = "left";
      k = "down";
      i = "up";
      l = "right";

      # Navigation
      u = "home";
      o = "end";
      y = "pageup";
      h = "pagedown";

      # Editing
      p = "delete";
      semicolon = "backspace";
      n = "enter";
      m = "tab";
      space = "enter";

      # Modifiers
      # a = "layer(alt)";
      d = "layer(shift)";
    };

    altgr = {
      a = "macro(compose a \")";
      e = "é";
      i = "í";
      o = "ó";
      u = "ú";
      n = "macro(compose ~ n)";
      q = "macro(compose c =)";
      c = "macro(class space H)";
      l = "command(ls)";
      r = "macro(🤘)";
    };
  };
}
