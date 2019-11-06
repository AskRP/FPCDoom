//------------------------------------------------------------------------------
//
//  FPCDoom - Port of Doom to Free Pascal Compiler
//  Copyright (C) 1993-1996 by id Software, Inc.
//  Copyright (C) 2004-2007 by Jim Valavanis
//  Copyright (C) 2017-2019 by Jim Valavanis
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, inc., 59 Temple Place - Suite 330, Boston, MA
//  02111-1307, USA.
//
// DESCRIPTION:
//   Menu widget stuff, episode selection and such.
//
//------------------------------------------------------------------------------
//  E-Mail: jimmyvalavanis@yahoo.gr
//  Site  : https://sourceforge.net/projects/fpcdoom/
//------------------------------------------------------------------------------

{$I FPCDoom.inc}

unit m_menu;

interface

uses
  d_event;

//
// MENUS
//

{ Called by main loop, }
{ saves config file and calls I_Quit when user exits. }
{ Even when the menu is not displayed, }
{ this can resize the view and change game parameters. }
{ Does all the real work of the menu interaction. }

function M_Responder(ev: Pevent_t): boolean;

{ Called by main loop, }
{ only used for menu (skull cursor) animation. }
procedure M_Ticker;

{ Called by main loop, }
{ draws the menus directly into the screen buffer. }
procedure M_Drawer;

{ Called by D_DoomMain, }
{ loads the config file. }
procedure M_Init;

{ Called by intro code to force menu up upon a keypress, }
{ does nothing if menu is already up. }
procedure M_StartControlPanel;

var
//
// defaulted values
//
  mouseSensitivity: integer;  // has default
  mouseSensitivityX: integer;
  mouseSensitivityY: integer;

// Show messages has default, 0 = off, 1 = on
  showMessages: integer;

  shademenubackground: integer;

  keepsavegamename: boolean;

  menuactive: boolean;

  inhelpscreens: boolean;

  menubackgroundflat: string = 'FLOOR4_6';

const
  DEFMENUBACKGROUNDFLAT = 'FLOOR4_6';

procedure M_InitMenus;

procedure M_SetKeyboardMode(const mode: integer);

implementation

uses
  d_fpc,
  doomdef,
  am_map,
  c_cmds,
  d_english,
  d_main,
  d_player,
  g_game,
  m_argv,
  m_misc,
  i_system,
  i_io,
  i_sound,
  e_endoom,
  i_video,
  p_mobj_h,
  p_terrain,
  p_enemy,
  r_aspect,
  r_data,
  r_main,
  r_hires,
  r_intrpl,
  r_lightmap,
  r_mirror,
  r_grayscale,
  r_colorsubsampling,
  t_main,
  z_memory,
  v_screenresolution,
  v_video,
  w_wad,
  hu_stuff,
  s_sound,
  doomstat,
// Data.
  sounds;

var
// temp for screenblocks (0-9)
  m_screensize: integer;

// -1 = no quicksave slot picked!
  quickSaveSlot: integer;

 // 1 = message to be printed
  messageToPrint: integer;
// ...and here is the message string!
  messageString: string;

  messageLastMenuActive: boolean;

// timed message = no input from user
  messageNeedsInput: boolean;

type
  PmessageRoutine = function(i: integer): pointer;

var
  messageRoutine: PmessageRoutine;


const
  SAVESTRINGSIZE = 24;

var
  gammamsg: array[0..GAMMASIZE - 1] of string;

// we are going to be entering a savegame string
  saveStringEnter: boolean;
  saveSlot: integer;  // which slot to save in
  saveCharIndex: integer; // which char we're editing
// old save description before edit
  saveOldString: string;

const
  SKULLXOFF = -32;
  SKULLYOFF = -5;
  ARROWXOFF = -8;
  LINEHEIGHT = 16;
  LINEHEIGHT2 = 8;


var
  savegamestrings: array[0..9] of string;
  endstring: string;

type
  menuitem_t = record
    // 0 = no cursor here, 1 = ok, 2 = arrows ok
    status: smallint;

    name: string;
    cmd: string;

    // choice = menu item #.
    // if status = 2,
    //   choice=0:leftarrow,1:rightarrow
    routine: PmessageRoutine;

    // Yes/No location
    pBoolVal: PBoolean;
    // hotkey in menu
    alphaKey: char;
  end;
  Pmenuitem_t = ^menuitem_t;
  menuitem_tArray = packed array[0..$FFFF] of menuitem_t;
  Pmenuitem_tArray = ^menuitem_tArray;

  Pmenu_t = ^menu_t;
  menu_t = record
    title: string[20];
    numitems: smallint;         // # of menu items
    prevMenu: Pmenu_t;          // previous menu
    leftMenu: Pmenu_t;          // left menu
    rightMenu: Pmenu_t;         // right menu
    menuitems: Pmenuitem_tArray;// menu items
    drawproc: PProcedure;       // draw routine
    x: smallint;
    y: smallint;                // x,y of menu
    lastOn: smallint;           // last item user was on in menu
    itemheight: integer;
    texturebk: boolean;
  end;

var
  itemOn: smallint;             // menu item skull is on
  skullAnimCounter: smallint;   // skull animation counter
  whichSkull: smallint;         // which skull to draw

// graphic name of skulls
// warning: initializer-string for array of chars is too long
  skullName: array[0..1] of string;

// current menudef
  currentMenu: Pmenu_t;

//
//      Menu Functions
//
procedure M_DrawThermo(x, y, thermWidth, thermDot: integer); overload;
var
  xx: integer;
  i: integer;
begin
  xx := x;
  V_DrawPatch(xx, y, SCN_TMP, 'M_THERML', false);
  xx := xx + 8;
  for i := 0 to thermWidth - 1 do
  begin
    V_DrawPatch(xx, y, SCN_TMP, 'M_THERMM', false);
    xx := xx + 8;
  end;
  V_DrawPatch(xx, y, SCN_TMP, 'M_THERMR', false);

  V_DrawPatch((x + 8) + thermDot * 8, y, SCN_TMP,
    'M_THERMO', false);
end;

procedure M_DrawThermo(x, y, thermWidth, thermDot, numdots: integer); overload;
var
  xx: integer;
  i: integer;
begin
  xx := x;
  V_DrawPatch(xx, y, SCN_TMP, 'M_THERML', false);
  xx := xx + 8;
  for i := 0 to thermWidth - 1 do
  begin
    V_DrawPatch(xx, y, SCN_TMP, 'M_THERMM', false);
    xx := xx + 8;
  end;
  V_DrawPatch(xx, y, SCN_TMP, 'M_THERMR', false);

  V_DrawPatch((x + 8) + (thermDot * 8 * thermWidth) div numdots, y, SCN_TMP,
    'M_THERMO', false);
end;

procedure M_DrawEmptyCell(menu: Pmenu_t; item: integer);
begin
  V_DrawPatch(menu.x - 10, menu.y + item * menu.itemheight - 1, SCN_TMP,
    'M_CELL1', false);
end;

procedure M_DrawSelCell(menu: Pmenu_t; item: integer);
begin
  V_DrawPatch(menu.x - 10, menu.y + item * menu.itemheight - 1, SCN_TMP,
    'M_CELL2', false);
end;

procedure M_StartMessage(const str: string; routine: PmessageRoutine; const input: boolean);
begin
  messageLastMenuActive := menuactive;
  messageToPrint := 1;
  messageString := str;
  if Assigned(routine) then
    @messageRoutine := @routine
  else
    messageRoutine := nil;
  messageNeedsInput := input;
  menuactive := true;
end;

procedure M_StopMessage;
begin
  menuactive := messageLastMenuActive;
  messageToPrint := 0;
end;

//
// Find string width from hu_font chars
//
function M_StringWidth(const str: string): integer;
var
  i: integer;
  c: integer;
begin
  result := 0;
  for i := 1 to Length(str) do
  begin
    c := Ord(toupper(str[i])) - Ord(HU_FONTSTART);
    if (c < 0) or (c >= HU_FONTSIZE) then
      result := result + 4
    else
      result := result + hu_font[c].width;
  end;
end;

//
//      Find string height from hu_font chars
//
function M_StringHeight(const str: string): integer;
var
  i: integer;
  height: integer;
begin
  height := hu_font[0].height;

  result := height;
  for i := 1 to Length(str) do
    if str[i] = #13 then
      result := result + height;
end;

//
//      Write a string using the hu_font
//
type
  menupos_t = record
    x, y: integer;
  end;

function M_WriteText(x, y: integer; const str: string): menupos_t;
var
  w: integer;
  ch: integer;
  c: integer;
  cx: integer;
  cy: integer;
  len: integer;
begin
  len := Length(str);
  if len = 0 then
  begin
    result.x := x;
    result.y := y;
    exit;
  end;

  ch := 1;
  cx := x;
  cy := y;

  while true do
  begin
    if ch > len then
      break;

    c := Ord(str[ch]);
    inc(ch);

    if c = 0 then
      break;

    if c = 10 then
    begin
      cx := x;
      continue;
    end;

    if c = 13 then
    begin
      cy := cy + 12;
      continue;
    end;

    c := Ord(toupper(Chr(c))) - Ord(HU_FONTSTART);
    if (c < 0) or (c >= HU_FONTSIZE) then
    begin
      cx := cx + 4;
      continue;
    end;

    w := hu_font[c].width;
    if (cx + w) > 320 then
      break;
    V_DrawPatch(cx, cy, SCN_TMP, hu_font[c], false);
    cx := cx + w;
  end;

  result.x := cx;
  result.y := cy;
end;

function M_WriteColorText(x, y: integer; const str: string; const clmap: string): menupos_t;
var
  w: integer;
  ch: integer;
  c: integer;
  cx: integer;
  cy: integer;
  len: integer;
  oldtranslation: PByteArray;
begin
  len := Length(str);
  if len = 0 then
  begin
    result.x := x;
    result.y := y;
    exit;
  end;

  ch := 1;
  cx := x;
  cy := y;

  oldtranslation := v_translation;
  v_translation := W_CacheLumpName(clmap, PU_STATIC);
  while true do
  begin
    if ch > len then
      break;

    c := Ord(str[ch]);
    inc(ch);

    if c = 0 then
      break;

    if c = 10 then
    begin
      cx := x;
      continue;
    end;

    if c = 13 then
    begin
      cy := cy + 12;
      continue;
    end;

    c := Ord(toupper(Chr(c))) - Ord(HU_FONTSTART);
    if (c < 0) or (c >= HU_FONTSIZE) then
    begin
      cx := cx + 4;
      continue;
    end;

    w := hu_font[c].width;
    if (cx + w) > 320 then
      break;
    V_DrawPatch(cx, cy, SCN_TMP, hu_font[c], false);
    cx := cx + w;
  end;
  Z_ChangeTag(v_translation, PU_CACHE);
  v_translation := oldtranslation;

  result.x := cx;
  result.y := cy;
end;

//
// M_ClearMenus
//
procedure M_ClearMenus;
begin
  menuactive := false;
end;

//
// M_SetupNextMenu
//
procedure M_SetupNextMenu(menudef: Pmenu_t);
begin
  currentMenu := menudef;
  itemOn := currentMenu.lastOn;
end;

//
// MENU DEFINITIONS
//
type
//
// DOOM MENU
//
  main_e = (
    mm_newgame,
    mm_options,
    mm_loadgame,
    mm_savegame,
    mm_readthis,
    mm_quitdoom,
    main_end
  );

var
  MainMenu: array[0..5] of menuitem_t;
  MainDef: menu_t;

type
//
// EPISODE SELECT
//
  episodes_e = (
    ep1,
    ep2,
    ep3,
    ep4,
    ep_end
  );

var
  EpisodeMenu: array[0..3] of menuitem_t;
  EpiDef: menu_t;

type
//
// NEW GAME
//
  newgame_e = (
    killthings,
    toorough,
    hurtme,
    violence,
    nightmare,
    newg_end
  );

var
  NewGameMenu: array[0..4] of menuitem_t;
  NewDef: menu_t;

type
//
// OPTIONS MENU
//
  options_e = (
    opt_general,
    opt_display,
    opt_sound,
    opt_compatibility,
    opt_controls,
    opt_system,
    opt_end
  );

var
  OptionsMenu: array[0..Ord(opt_end) - 1] of menuitem_t;
  OptionsDef: menu_t;

// GENERAL MENU
type
  optionsgeneral_e = (
    endgame,
    messages,
    scrnsize,
    option_empty1,
    optgen_end
  );

var
  OptionsGeneralMenu: array[0..Ord(optgen_end) - 1] of menuitem_t;
  OptionsGeneralDef: menu_t;

// DISPLAY MENU
type
  optionsdisplay_e = (
    od_detail,
    od_automap,
    od_appearance,
    od_advanced,
    od_colors,
    od_lightmap,
    od_32bitsetup,
    optdisp_end
  );

var
  OptionsDisplayMenu: array[0..Ord(optdisp_end) - 1] of menuitem_t;
  OptionsDisplayDef: menu_t;

// DISPLAY DETAIL MENU
type
  optionsdisplaydetail_e = (
    odd_detaillevel,
    odd_screensize,
    odd_filler1,
    odd_filler2,
    odd_setvideomode,
    optdispdetail_end
  );

var
  OptionsDisplayDetailMenu: array[0..Ord(optdispdetail_end) - 1] of menuitem_t;
  OptionsDisplayDetailDef: menu_t;

// DISPLAY APPEARANCE MENU
type
  optionsdisplayappearance_e = (
    od_drawfps,
    od_shademenubackground,
    od_displayendscreen,
    optdispappearance_end
  );

var
  OptionsDisplayAppearanceMenu: array[0..Ord(optdispappearance_end) - 1] of menuitem_t;
  OptionsDisplayAppearanceDef: menu_t;

// DISPLAY AUTOMAP MENU
type
  optionsdisplayautomap_e = (
    od_automapoverlay,
    od_automaprotate,
    optdispautomap_end
  );

var
  OptionsDisplayAutomapMenu: array[0..Ord(optdispautomap_end) - 1] of menuitem_t;
  OptionsDisplayAutomapDef: menu_t;

// DISPLAY ADVANCED MENU
type
  optionsdisplayadvanced_e = (
    od_fullscreen,
    od_mirror,
    od_usetransparentsprites,
    od_interpolate,
    od_zaxisshift,
    od_chasecamera,
    od_fixstallhack,
    od_widescreensupport,
    od_excludewidescreenplayersprites,
    optdispadvanced_end
  );

var
  OptionsDisplayAdvancedMenu: array[0..Ord(optdispadvanced_end) - 1] of menuitem_t;
  OptionsDisplayAdvancedDef: menu_t;

// COLORS MENU
type
  optionsdisplaycolors_e = (
    oc_grayscale,
    oc_colorsubsubling,
    optdispcolors_end
  );

var
  OptionsDisplayColorsMenu: array[0..Ord(optdispcolors_end) - 1] of menuitem_t;
  OptionsDisplayColorsDef: menu_t;

// LIGHTMAP OPTIONS
type
  optionslightmap_e = (
    ol_uselightmaps,
    ol_accuracy,
    ol_colorintensity,
    ol_filler1,
    ol_lightwidthfactor,
    ol_filler2,
    od_resettodefaults,
    ol_lightmap_end
  );

var
  OptionsLightmapMenu: array[0..Ord(ol_lightmap_end) - 1] of menuitem_t;
  OptionsLightmapDef: menu_t;

// DISPLAY 32 BIT RENDERING MENU
type
  optionsdisplay32bit_e = (
    od_forcecolormaps,
    od_32bittexturepaletteeffects,
    od_use32bitfuzzeffect,
    od_useexternaltextures,
    od_preferetexturesnamesingamedirectory,
    od_flatfiltering,
    optdisp32bit_end
  );

var
  OptionsDisplay32bitMenu: array[0..Ord(optdisp32bit_end) - 1] of menuitem_t;
  OptionsDisplay32bitDef: menu_t;

type
//
// Read This! MENU 1 & 2
//
  read_e = (
    rdthsempty1,
    read1_end
  );

var
  ReadMenu1: array[0..0] of menuitem_t;
  ReadDef1: menu_t;

type
  read_e2 = (
    rdthsempty2,
    read2_end
  );

var
  ReadMenu2: array[0..0] of menuitem_t;
  ReadDef2: menu_t;

type
//
// SOUND MENU
//
  sound_e = (
    snd_volume,
    snd_usewav,
    snd_preferewavnamesingamedirectory,
    sound_end
  );

var
  SoundMenu: array[0..Ord(sound_end) - 1] of menuitem_t;
  SoundDef: menu_t;

type
//
// SOUND VOLUME MENU
//
  soundvol_e = (
    sfx_vol,
    sfx_empty1,
    music_vol,
    sfx_empty2,
    soundvol_end
  );

var
  SoundVolMenu: array[0..Ord(soundvol_end) - 1] of menuitem_t;
  SoundVolDef: menu_t;

type
//
// COMPATIBILITY MENU
//
  compatibility_e = (
    cmp_allowplayerjumps,
    cmp_keepcheatsinplayerrebord,
    cmp_majorbossdeathendsdoom1level,
    cmp_spawnrandommonsters,
    cmp_allowterrainsplashes,
    cmp_continueafterplayerdeath,
    cmp_end
  );

var
  CompatibilityMenu: array[0..Ord(cmp_end) - 1] of menuitem_t;
  CompatibilityDef: menu_t;

type
//
// CONTROLS MENU
//
  controls_e = (
    ctrl_usemouse,
    ctrl_invertmouselook,
    ctrl_invertmouseturn,
    cttl_mousesensitivity,
    ctrl_usejoystic,
    ctrl_autorun,
    ctrl_keyboardmode,
    ctrl_keybindings,
    ctrl_end
  );

var
  ControlsMenu: array[0..Ord(ctrl_end) - 1] of menuitem_t;
  ControlsDef: menu_t;

type
//
// MOUSE SENSITIVITY MENU
//
  sensitivity_e = (
    sens_mousesensitivity,
    sens_empty1,
    sens_empty2,
    sens_mousesensitivityx,
    sens_empty3,
    sens_empty4,
    sens_mousesensitivityy,
    sens_empty5,
    sens_empty6,
    sens_end
  );

var
  SensitivityMenu: array[0..Ord(sens_end) - 1] of menuitem_t;
  SensitivityDef: menu_t;


type
//
// KEY BINDINGS MENU
//
  keybindings_e = (
    kb_up,
    kb_down,
    kb_left,
    kb_right,
    kb_strafeleft,
    kb_straferight,
    kb_jump,
    kb_fire,
    kb_use,
    kb_strafe,
    kb_speed,
    kb_lookup,
    kb_lookdown,
    kb_lookcenter,
    kb_lookleft,
    kb_lookright,
//    kb_lookforward,
    kb_end
  );

var
  KeyBindingsMenu: array[0..Ord(kb_end) - 1] of menuitem_t;
  KeyBindingsDef: menu_t;

type
  bindinginfo_t = record
    text: string[20];
    pkey: PInteger;
  end;

const
  KeyBindingsInfo: array [0..Ord(kb_end) - 1] of bindinginfo_t = (
    (text: 'Move forward'; pkey: @key_up),
    (text: 'Move backward'; pkey: @key_down),
    (text: 'Turn left'; pkey: @key_left),
    (text: 'Turn right'; pkey: @key_right),
    (text: 'Strafe left'; pkey: @key_strafeleft),
    (text: 'Strafe right'; pkey: @key_straferight),
    (text: 'Jump'; pkey: @key_jump),
    (text: 'Fire'; pkey: @key_fire),
    (text: 'Use'; pkey: @key_use),
    (text: 'Strafe'; pkey: @key_strafe),
    (text: 'Run'; pkey: @key_speed),
    (text: 'Look up'; pkey: @key_lookup),
    (text: 'Look down'; pkey: @key_lookdown),
    (text: 'Look center'; pkey: @key_lookcenter),
    (text: 'Look left'; pkey: @key_lookleft),
    (text: 'Look right'; pkey: @key_lookright){,
    (text: 'Look forward'; pkey: @key_lookforward)}
  );

var
  bindkeyEnter: boolean;
  bindkeySlot: integer;
  saveOldkey: integer;

function M_KeyToString(const k: integer): string;
begin
  if (k >= 33) and (k <= 126) then
  begin
    result := Chr(k);
    if result = '=' then
      result := '+'
    else if result = ',' then
      result := '<'
    else if result = '.' then
      result := '>';
    exit;
  end;

  case k of
    32: result := 'SPACE';
    KEY_RIGHTARROW: result := 'RIGHTARROW';
    KEY_LEFTARROW: result := 'LEFTARROW';
    KEY_UPARROW: result := 'UPARROW';
    KEY_DOWNARROW: result := 'DOWNARROW';
    KEY_ESCAPE: result := 'ESCAPE';
    KEY_ENTER: result := 'ENTER';
    KEY_TAB: result := 'TAB';
    KEY_F1: result := 'F1';
    KEY_F2: result := 'F2';
    KEY_F3: result := 'F3';
    KEY_F4: result := 'F4';
    KEY_F5: result := 'F5';
    KEY_F6: result := 'F6';
    KEY_F7: result := 'F7';
    KEY_F8: result := 'F8';
    KEY_F9: result := 'F9';
    KEY_F10: result := 'F10';
    KEY_F11: result := 'F11';
    KEY_F12: result := 'F12';
    KEY_PRNT: result := 'PRNT';
    KEY_CON: result := 'CON';
    KEY_BACKSPACE: result := 'BACKSPACE';
    KEY_PAUSE: result := 'PAUSE';
    KEY_EQUALS: result := 'EQUALS';
    KEY_MINUS: result := 'MINUS';
    KEY_RSHIFT: result := 'RSHIFT';
    KEY_RCTRL: result := 'RCTRL';
    KEY_RALT: result := 'ALT';
    KEY_PAGEDOWN: result := 'PAGEDOWN';
    KEY_PAGEUP: result := 'PAGEUP';
    KEY_INS: result := 'INS';
    KEY_HOME: result := 'HOME';
    KEY_END: result := 'END';
    KEY_DELETE: result := 'DELETE';
  else
    result := '';
  end;
end;

function M_SetKeyBinding(const slot: integer; key: integer): boolean;
var
  i: integer;
  oldk: integer;
begin
  if (slot < 0) or (slot >= Ord(kb_end)) then
  begin
    result := false;
    exit;
  end;

  if key = 18 then
    key := KEY_RALT;

  result := key in [32..125,
    KEY_RIGHTARROW,
    KEY_LEFTARROW,
    KEY_UPARROW,
    KEY_DOWNARROW,
    KEY_BACKSPACE,
    KEY_RSHIFT,
    KEY_RCTRL,
    KEY_RALT,
    KEY_PAGEDOWN,
    KEY_PAGEUP,
    KEY_INS,
    KEY_HOME,
    KEY_END,
    KEY_DELETE
  ];

  if not result then
    exit;

  oldk := KeyBindingsInfo[slot].pkey^;
  for i := 0 to Ord(kb_end) - 1 do
    if i <> slot then
     if KeyBindingsInfo[i].pkey^ = key then
       KeyBindingsInfo[i].pkey^ := oldk;
  KeyBindingsInfo[slot].pkey^ := key;
end;

procedure M_DrawBindings;
var
  i: integer;
  len: integer;
  s: string;
  drawkey: boolean;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  for i := 0 to Ord(kb_end) - 1 do
  begin
    s := KeyBindingsInfo[i].text + ': ';
    len := M_StringWidth(s);
    M_WriteText(KeyBindingsDef.x, KeyBindingsDef.y + KeyBindingsDef.itemheight * i, s);
    drawkey := true;
    if bindkeyEnter then
      if i = bindkeySlot then
        if (gametic div 18) mod 2 <> 0 then
          drawkey := false;
    if drawkey then
      M_WriteColorText(KeyBindingsDef.x + len, KeyBindingsDef.y + KeyBindingsDef.itemheight * i, M_KeyToString(KeyBindingsInfo[i].pkey^), 'CRGRAY');
  end;
end;

//
// Select key binding
//
procedure M_KeyBindingSelect(choice: integer);
begin
  bindkeyEnter := true;

  bindkeySlot := choice;

  saveOldkey := KeyBindingsInfo[choice].pkey^;
end;


type
//
// SYSTEM  MENU
//
  system_e = (
    sys_safemode,
    sys_usemmx,
    sys_end
  );

var
  SystemMenu: array[0..Ord(sys_end) - 1] of menuitem_t;
  SystemDef: menu_t;

var
  LoadMenu: array[0..Ord(load_end) - 1] of menuitem_t;
  LoadDef: menu_t;
  SaveMenu: array[0..Ord(load_end) - 1] of menuitem_t;
  SaveDef: menu_t;

//
// M_ReadSaveStrings
//  read the strings from the savegame files
//
procedure M_ReadSaveStrings;
var
  handle: file;
  i: integer;
  name: string;
begin
  for i := 0 to Ord(load_end) - 1 do
  begin
    sprintf(name, M_SaveFileName(SAVEGAMEPATH + '\' + SAVEGAMEIWAD + '\' + SAVEGAMENAME) + '%d.dsg', [i]);

    if not fopen(handle, name, fOpenReadOnly) then
    begin
      savegamestrings[i] := '';
      LoadMenu[i].status := 0;
      continue;
    end;
    SetLength(savegamestrings[i], SAVESTRINGSIZE);
    BlockRead(handle, (@savegamestrings[i][1])^, SAVESTRINGSIZE);
    close(handle);
    LoadMenu[i].status := 1;
  end;
end;

//
// Draw border for the savegame description
//
procedure M_DrawSaveLoadBorder(x, y: integer);
var
  i: integer;
begin
  V_DrawPatch(x - 8, y + 7, SCN_TMP, 'M_LSLEFT', false);

  for i := 0 to 23 do
  begin
    V_DrawPatch (x, y + 7, SCN_TMP, 'M_LSCNTR', false);
    x := x + 8;
  end;

  V_DrawPatch(x, y + 7, SCN_TMP, 'M_LSRGHT', false);
end;

//
// M_LoadGame & Cie.
//
procedure M_DrawLoad;
var
  i: integer;
begin
  V_DrawPatch(72, LoadDef.y - 26, SCN_TMP, 'M_LOADG', false);
  for i := 0 to Ord(load_end) - 1 do
  begin
    M_DrawSaveLoadBorder(LoadDef.x, LoadDef.y + LoadDef.itemheight * i);
    M_WriteText(LoadDef.x, LoadDef.y + LoadDef.itemheight * i, savegamestrings[i]);
  end;
end;

//
// User wants to load this game
//
procedure M_LoadSelect(choice: integer);
var
  name: string;
begin
  sprintf(name, M_SaveFileName(SAVEGAMEPATH + '\' + SAVEGAMEIWAD + '\' + SAVEGAMENAME) + '%d.dsg', [choice]);
  G_LoadGame(name);
  M_ClearMenus;
end;

//
// Selected from DOOM menu
//
procedure M_LoadGame(choice: integer);
begin
  if netgame then
  begin
    M_StartMessage(LOADNET + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  M_SetupNextMenu(@LoadDef);
  M_ReadSaveStrings;
end;

//
//  M_SaveGame & Cie.
//
procedure M_DrawSave;
var
  i: integer;
begin
  V_DrawPatch(72, LoadDef.y - 28, SCN_TMP, 'M_SAVEG', false);
  for i := 0 to Ord(load_end) - 1 do
  begin
    M_DrawSaveLoadBorder(LoadDef.x, LoadDef.y + LoadDef.itemheight * i);
    M_WriteText(LoadDef.x, LoadDef.y + LoadDef.itemheight * i, savegamestrings[i]);
  end;

  if saveStringEnter then
  begin
    i := M_StringWidth(savegamestrings[saveSlot]);
    if (gametic div 18) mod 2 = 0 then
      M_WriteText(LoadDef.x + i, LoadDef.y + LoadDef.itemheight * saveSlot, '_');
  end;
end;

//
// M_Responder calls this when user is finished
//
procedure M_DoSave(slot: integer);
begin
  G_SaveGame(slot, savegamestrings[slot]);
  M_ClearMenus;

  // PICK QUICKSAVE SLOT YET?
  if (quickSaveSlot = -2) then
    quickSaveSlot := slot;
end;

//
// User wants to save. Start string input for M_Responder
//
procedure M_SaveSelect(choice: integer);
var
  s: string;
  i: integer;
  c: char;
begin
  // we are going to be intercepting all chars
  saveStringEnter := true;

  saveSlot := choice;
  saveOldString := savegamestrings[choice];
  // JVAL 21/4/2017
  if keepsavegamename then
  begin
    s := '';
    for i := 1 to Length(savegamestrings[choice]) do
    begin
      c := savegamestrings[choice][i];
      if c in [#0, #13, #10, ' '] then
        Break
      else
        s := s + c;
    end;
    savegamestrings[choice] := s;
  end
  else if savegamestrings[choice] <> '' then
    savegamestrings[choice] := '';
  saveCharIndex := Length(savegamestrings[choice]);
end;

//
// Selected from DOOM menu
//
procedure M_SaveGame(choice: integer);
begin
  if not usergame then
  begin
    M_StartMessage(SAVEDEAD + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  if gamestate <> GS_LEVEL then
    exit;

  M_SetupNextMenu(@SaveDef);
  M_ReadSaveStrings;
end;

//
//      M_QuickSave
//
procedure M_SwtchnSound;
begin
  S_StartSound(nil, Ord(sfx_swtchn));
end;

procedure M_SwtchxSound;
begin
  S_StartSound(nil, Ord(sfx_swtchx));
end;


procedure M_QuickSaveResponse(ch: integer);
begin
  if ch = Ord('y') then
  begin
    M_DoSave(quickSaveSlot);
    M_SwtchxSound;
  end;
end;

procedure M_QuickSave;
var
  tempstring: string;
begin
  if not usergame then
  begin
    S_StartSound(nil, Ord(sfx_oof));
    exit;
  end;

  if gamestate <> GS_LEVEL then
    exit;

  if quickSaveSlot < 0 then
  begin
    M_StartControlPanel;
    M_ReadSaveStrings;
    M_SetupNextMenu(@SaveDef);
    quickSaveSlot := -2;  // means to pick a slot now
    exit;
  end;

  sprintf(tempstring, QSPROMPT + #13#10 + PRESSYN, [savegamestrings[quickSaveSlot]]);
  M_StartMessage(tempstring, @M_QuickSaveResponse, true);
end;

//
// M_QuickLoad
//
procedure M_QuickLoadResponse(ch: integer);
begin
  if ch = Ord('y') then
  begin
    M_LoadSelect(quickSaveSlot);
    M_SwtchxSound;
  end;
end;

procedure M_QuickLoad;
var
  tempstring: string;
begin
  if netgame then
  begin
    M_StartMessage(QLOADNET + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  if quickSaveSlot < 0 then
  begin
    M_StartMessage(QSAVESPOT + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  sprintf(tempstring, QLPROMPT + #13#10 + PRESSYN, [savegamestrings[quickSaveSlot]]);
  M_StartMessage(tempstring, @M_QuickLoadResponse, true);
end;

//
// Read This Menus
// Had a "quick hack to fix romero bug"
//
procedure M_DrawReadThis1;
begin
  inhelpscreens := true;
  case gamemode of
    commercial:
      V_PageDrawer(pg_HELP);
    shareware,
    registered,
    retail:
      V_PageDrawer(pg_HELP1);
  end;
end;

//
// Read This Menus - optional second page.
//
procedure M_DrawReadThis2;
begin
  inhelpscreens := true;
  case gamemode of
    retail,
    commercial:
      // This hack keeps us from having to change menus.
      V_PageDrawer(pg_CREDIT);
    shareware,
    registered:
      V_PageDrawer(pg_HELP2);
  end;
end;

//
// Change Sfx & Music volumes
//
procedure M_DrawSoundVol;
begin
  V_DrawPatch(60, 38, SCN_TMP, 'M_SVOL', false);

  M_DrawThermo(
    SoundVolDef.x, SoundVolDef.y + SoundVolDef.itemheight * (Ord(sfx_vol) + 1), 16, snd_SfxVolume);

  M_DrawThermo(
    SoundVolDef.x, SoundVolDef.y + SoundVolDef.itemheight * (Ord(music_vol) + 1), 16, snd_MusicVolume);
end;

procedure M_DrawCompatibility;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_COM', false);
end;

const
  mkeyboardmodes: array[0..3] of string = ('ARROWS', 'WASD', 'ESDF', 'CUSTOM');

procedure M_SetKeyboardMode(const mode: integer);
begin
  if mode = 0 then
  begin
    key_right := 174;
    key_left := 172;
    key_up := 173;
    key_down := 175;
    key_strafeleft := 44;
    key_straferight := 46;
    key_jump := 97;
    key_fire := 157;
    key_use := 32;
    key_strafe := 184;
    key_speed := 182;
    key_lookup := 197;
    key_lookdown := 202;
    key_lookcenter := 199;
    key_lookright := 198;
    key_lookleft := 200;
    key_lookforward := 13;
  end
  else if mode = 1 then
  begin
    key_right := 174;
    key_left := 172;
    key_up := 119;
    key_down := 115;
    key_strafeleft := 97;
    key_straferight := 100;
    key_jump := 106;
    key_fire := 157;
    key_use := 32;
    key_strafe := 184;
    key_speed := 182;
    key_lookup := 197;
    key_lookdown := 202;
    key_lookcenter := 199;
    key_lookright := 198;
    key_lookleft := 200;
    key_lookforward := 13;
  end
  else if mode = 2 then
  begin
    key_right := 174;
    key_left := 172;
    key_up := 101;
    key_down := 100;
    key_strafeleft := 115;
    key_straferight := 102;
    key_jump := 97;
    key_fire := 157;
    key_use := 32;
    key_strafe := 184;
    key_speed := 182;
    key_lookup := 197;
    key_lookdown := 202;
    key_lookcenter := 199;
    key_lookright := 198;
    key_lookleft := 200;
    key_lookforward := 13;
  end;
end;

function M_GetKeyboardMode: integer;
begin
  if (key_right = 174) and
     (key_left = 172) and
     (key_up = 173) and
     (key_down = 175) and
     (key_strafeleft = 44) and
     (key_straferight = 46) and
     (key_jump = 97) and
     (key_fire = 157) and
     (key_use = 32) and
     (key_strafe = 184) and
     (key_speed = 182) and
     (key_lookup = 197) and
     (key_lookdown = 202) and
     (key_lookcenter = 199) and
     (key_lookright = 198) and
     (key_lookleft = 200) and
     (key_lookforward = 13) then
  begin
    result := 0;
    exit;
  end;

  if (key_right = 174) and
     (key_left = 172) and
     (key_up = 119) and
     (key_down = 115) and
     (key_strafeleft = 97) and
     (key_straferight = 100) and
     (key_jump = 106) and
     (key_fire = 157) and
     (key_use = 32) and
     (key_strafe = 184) and
     (key_speed = 182) and
     (key_lookup = 197) and
     (key_lookdown = 202) and
     (key_lookcenter = 199) and
     (key_lookright = 198) and
     (key_lookleft = 200) and
     (key_lookforward = 13) then
  begin
    result := 1;
    exit;
  end;

  if (key_right = 174) and
     (key_left = 172) and
     (key_up = 101) and
     (key_down = 100) and
     (key_strafeleft = 115) and
     (key_straferight = 102) and
     (key_jump = 97) and
     (key_fire = 157) and
     (key_use = 32) and
     (key_strafe = 184) and
     (key_speed = 182) and
     (key_lookup = 197) and
     (key_lookdown = 202) and
     (key_lookcenter = 199) and
     (key_lookright = 198) and
     (key_lookleft = 200) and
     (key_lookforward = 13) then
  begin
    result := 2;
    exit;
  end;

  result := 3;
end;

procedure M_KeyboardModeArrows;
begin
  M_SetKeyboardMode(0);
end;

procedure M_KeyboardModeWASD;
begin
  M_SetKeyboardMode(1);
end;

procedure M_KeyboardModeESDF;
begin
  M_SetKeyboardMode(2);
end;

procedure M_SwitchKeyboardMode(choice: integer);
var
  old: integer;
begin
  old := M_GetKeyboardMode;
  case old of
    0: M_KeyboardModeWASD;
    1: M_KeyboardModeESDF;
  else
    M_KeyboardModeArrows;
  end;
end;

procedure M_CmdKeyboardMode(const parm1, parm2: string);
var
  wrongparms: boolean;
  sparm1: string;
begin
  wrongparms := false;

  if (parm1 = '') or (parm2 <> '') then
    wrongparms := true;

  sparm1 := strupper(parm1);

  if (parm1 <> '0') and (parm1 <> '1') and (parm1 <> '2') and
     (sparm1 <> 'ARROWS') and (sparm1 <> 'WASD') and (sparm1 <> 'ESDF') then
    wrongparms := true;

  if wrongparms then
  begin
    printf('Specify the keyboard mode:'#13#10);
    printf('  0: Arrows'#13#10);
    printf('  1: WASD'#13#10);
    printf('  2: ESDF'#13#10);
    exit;
  end;

  if (parm1 = '0') or (sparm1 = 'ARROWS') then
    M_SetKeyboardMode(0)
  else if (parm1 = '1') or (sparm1 = 'WASD') then
    M_SetKeyboardMode(1)
  else
    M_SetKeyboardMode(2);
end;

procedure M_KeyBindings(choice: integer);
begin
  M_SetupNextMenu(@KeyBindingsDef);
end;

procedure M_DrawControls;
var
  ppos: menupos_t;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_CON', false);

  ppos := M_WriteText(ControlsDef.x, ControlsDef.y + ControlsDef.itemheight * Ord(ctrl_keyboardmode), 'Keyboard movement: ');
  M_WriteColorText(ppos.x, ppos.y, mkeyboardmodes[M_GetKeyboardMode], 'CRGRAY');
end;

procedure M_DrawSound;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_SOU', false);
end;

procedure M_DrawSystem;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_SYS', false);
end;

procedure M_OptionsSound(choice: integer);
begin
  M_SetupNextMenu(@SoundDef);
end;

procedure M_SoundVolume(choice: integer);
begin
  M_SetupNextMenu(@SoundVolDef);
end;

procedure M_OptionsConrols(choice: integer);
begin
  M_SetupNextMenu(@ControlsDef);
end;

procedure M_OptionsSensitivity(choice: integer);
begin
  M_SetupNextMenu(@SensitivityDef);
end;

procedure M_OptionsCompatibility(choice: integer);
begin
  M_SetupNextMenu(@CompatibilityDef);
end;

procedure M_OptionsSystem(choice: integer);
begin
  M_SetupNextMenu(@SystemDef);
end;

procedure M_OptionsGeneral(choice: integer);
begin
  M_SetupNextMenu(@OptionsGeneralDef);
end;

procedure M_OptionsDisplay(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplayDef);
end;

var
  mdisplaymode_idx: integer = 0;

procedure M_OptionsDisplayDetail(choice: integer);
var
  idx: integer;
begin
  idx := I_NearestDisplayModeIndex(SCREENWIDTH, SCREENHEIGHT);
  if idx >= 0 then
    mdisplaymode_idx := idx;
  M_SetupNextMenu(@OptionsDisplayDetailDef);
end;

procedure M_OptionsDisplayAutomap(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplayAutomapDef);
end;

procedure M_OptionsDisplayAppearance(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplayAppearanceDef);
end;

procedure M_OptionsDisplayAdvanced(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplayAdvancedDef);
end;

procedure M_OptionsDisplayLightmap(choice: integer);
begin
  M_SetupNextMenu(@OptionsLightmapDef);
end;

procedure M_OptionsDisplayColors(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplayColorsDef);
end;

procedure M_OptionsDisplay32bit(choice: integer);
begin
  M_SetupNextMenu(@OptionsDisplay32bitDef);
end;

procedure M_SfxVol(choice: integer);
begin
  case choice of
    0: if snd_SfxVolume <> 0 then dec(snd_SfxVolume);
    1: if snd_SfxVolume < 15 then inc(snd_SfxVolume);
  end;
  S_SetSfxVolume(snd_SfxVolume);
end;

procedure M_MusicVol(choice: integer);
begin
  case choice of
    0: if snd_MusicVolume <> 0 then dec(snd_MusicVolume);
    1: if snd_MusicVolume < 15 then inc(snd_MusicVolume);
  end;
  S_SetMusicVolume(snd_MusicVolume);
end;

//
// M_DrawMainMenu
//
procedure M_DrawMainMenu;
begin
  V_DrawPatch(94, 2, SCN_TMP, 'M_DOOM', false);
end;

//
// M_NewGame
//
procedure M_DrawNewGame;
begin
  V_DrawPatch(96, 14, SCN_TMP, 'M_NEWG', false);
  V_DrawPatch(54, 38, SCN_TMP, 'M_SKILL', false);
end;

procedure M_NewGame(choice: integer);
begin
  if netgame and (not demoplayback) then
  begin
    M_StartMessage(SNEWGAME + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  if gamemode = commercial then
  begin
    if oldsharewareversion then
      NewDef.numitems := Ord(nightmare); // No nightmare in old shareware
    M_SetupNextMenu(@NewDef);
  end
  else
    M_SetupNextMenu(@EpiDef);
end;

//
//      M_Episode
//
var
  epi: integer;

procedure M_DrawEpisode;
begin
  V_DrawPatch(54, 38, SCN_TMP, 'M_EPISOD', false);
end;

procedure M_VerifyNightmare(ch: integer);
begin
  if ch <> Ord('y') then
    exit;

  G_DeferedInitNew(sk_nightmare, epi + 1, 1); // JVAL nightmare become sk_nightmare
  M_ClearMenus;
end;

procedure M_ChooseSkill(choice: integer);
begin
  if choice = Ord(nightmare) then
  begin
    M_StartMessage(SNIGHTMARE + #13#10 + PRESSYN, @M_VerifyNightmare, true);
    exit;
  end;

  G_DeferedInitNew(skill_t(choice), epi + 1, 1);
  M_ClearMenus;
end;

procedure M_Episode(choice: integer);
begin
  if (gamemode = shareware) and (choice <> 0) then
  begin
    M_StartMessage(SWSTRING + #13#10 + PRESSKEY, nil, false);
    M_SetupNextMenu(@ReadDef1);
    exit;
  end;

  // Yet another hack...
  if (gamemode = registered) and (choice > 2) then
  begin
    I_Warning('M_Episode(): 4th episode requires UltimateDOOM' + #13#10);
    choice := 0;
  end;

  epi := choice;

  if oldsharewareversion then
    NewDef.numitems := Ord(nightmare); // No nightmare in old shareware shareware
  M_SetupNextMenu(@NewDef);
end;

//
// M_Options
//
var
  msgNames: array[0..1] of string = ('M_MSGOFF', 'M_MSGON');

procedure M_DrawOptions;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
end;

procedure M_DrawGeneralOptions;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);

  V_DrawPatch(OptionsGeneralDef.x + 120, OptionsGeneralDef.y + OptionsGeneralDef.itemheight * Ord(messages), SCN_TMP,
    msgNames[showMessages], false);

  M_DrawThermo(
    OptionsGeneralDef.x, OptionsGeneralDef.y + OptionsGeneralDef.itemheight * (Ord(scrnsize) + 1), 9, m_screensize);
end;

procedure M_DrawSensitivity;
begin
  V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
  V_DrawPatch(20, 48, SCN_TMP, 'M_MSENS', false);

  M_DrawThermo(
    SensitivityDef.x, SensitivityDef.y + SensitivityDef.itemheight * (Ord(sens_mousesensitivity) + 1), 20, mouseSensitivity);

  M_DrawThermo(
    SensitivityDef.x, SensitivityDef.y + SensitivityDef.itemheight * (Ord(sens_mousesensitivityx) + 1), 11, mouseSensitivityX);

  M_DrawThermo(
    SensitivityDef.x, SensitivityDef.y + SensitivityDef.itemheight * (Ord(sens_mousesensitivityy) + 1), 11, mouseSensitivityY);
end;

procedure M_DrawDisplayOptions;
var
  lump: integer;
begin
  lump := W_CheckNumForName('M_DISOPT');
  if lump >= 0 then
    V_DrawPatch(52, 15, SCN_TMP, lump, false)
  else
    V_DrawPatch(108, 15, SCN_TMP, 'M_OPTTTL', false);
end;

var
  colordepths: array[boolean] of string = ('8bit', '32bit');

procedure M_DrawDisplayDetailOptions;
var
  stmp: string;
  ppos: menupos_t;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_DET', false);

  ppos := M_WriteText(OptionsDisplayDetailDef.x, OptionsDisplayDetailDef.y + OptionsDisplayDetailDef.itemheight * Ord(odd_detaillevel), 'Detail level: ');
  sprintf(stmp, '%s (%s)', [detailStrings[detailLevel], colordepths[videomode = vm32bit]]);
  M_WriteColorText(ppos.x, ppos.y, stmp, 'CRGRAY');

  if mdisplaymode_idx < 0 then
    mdisplaymode_idx := 0
  else if mdisplaymode_idx >= numdisplaymodes then
    mdisplaymode_idx := numdisplaymodes - 1;
  ppos := M_WriteText(OptionsDisplayDetailDef.x, OptionsDisplayDetailDef.y + OptionsDisplayDetailDef.itemheight * Ord(odd_screensize), 'Screen Size: ');
  sprintf(stmp, '(%dx%d)', [displaymodes[mdisplaymode_idx].width, displaymodes[mdisplaymode_idx].height]);
  M_WriteColorText(ppos.x, ppos.y, stmp, 'CRGRAY');

  M_DrawThermo(
    OptionsDisplayDetailDef.x, OptionsDisplayDetailDef.y + OptionsDisplayDetailDef.itemheight * (Ord(odd_screensize) + 1), 30, mdisplaymode_idx, numdisplaymodes);

  if (displaymodes[mdisplaymode_idx].width = SCREENWIDTH) and (displaymodes[mdisplaymode_idx].height = SCREENHEIGHT) then
    stmp := 'No change to screen size'
  else
    sprintf(stmp, 'Select to set screen size to %dx%d...', [displaymodes[mdisplaymode_idx].width, displaymodes[mdisplaymode_idx].height]);
  M_WriteText(OptionsDisplayDetailDef.x, OptionsDisplayDetailDef.y + OptionsDisplayDetailDef.itemheight * Ord(odd_setvideomode), stmp);
end;

procedure M_SwitchShadeMode(choice: integer);
begin
  shademenubackground := (shademenubackground + 1) mod 3;
end;

const
  menubackrounds: array[0..2] of string =
    ('NONE', 'SHADOW', 'TEXTURE');

procedure M_DrawDisplayAppearanceOptions;
var
  ppos: menupos_t;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_APP', false);

  ppos := M_WriteText(OptionsDisplayAppearanceDef.x, OptionsDisplayAppearanceDef.y + OptionsDisplayAppearanceDef.itemheight * Ord(od_shademenubackground), 'Menu background: ');
  M_WriteColorText(ppos.x, ppos.y, menubackrounds[shademenubackground mod 3], 'CRGRAY');
end;

procedure M_DrawDisplayAutomapOptions;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_MAP', false);
end;

procedure M_ChangeLightmapAccuracy(choice: integer);
begin
  lightmapaccuracymode := (lightmapaccuracymode + 1) mod 4;
end;

const
  str_lightmapaccuracymodes: array[0..3] of string =
    ('LOW', 'MEDIUM', 'HIGH', 'VERY HIGH & VERY SLOW');

var
  lightmapcolorintensityidx: integer = DEFLMCOLORSENSITIVITY div 8;

procedure M_ChangeLightmapColorIntensity(choice: integer);
begin
  case choice of
    0: if lightmapcolorintensityidx > 0 then
         dec(lightmapcolorintensityidx);
    1: if lightmapcolorintensityidx < (MAXLMCOLORSENSITIVITY - MINLMCOLORSENSITIVITY) div 8 then
         inc(lightmapcolorintensityidx);
  end;
  lightmapcolorintensity := MINLMCOLORSENSITIVITY + lightmapcolorintensityidx * 8;
end;

procedure M_ChangeLightmapLightWidthFactor(choice: integer);
begin
  case choice of
    0: if lightwidthfactor > MINLIGHTWIDTHFACTOR then
         dec(lightwidthfactor);
    1: if lightwidthfactor < MAXLIGHTWIDTHFACTOR then
         inc(lightwidthfactor);
  end;
end;

procedure M_LightmapDefaults(choice: integer);
begin
  lightmapaccuracymode := 0;
  lightmapcolorintensity := DEFLMCOLORSENSITIVITY;
  lightwidthfactor := DEFLIGHTWIDTHFACTOR;
end;

procedure M_DrawOptionsLightmap;
var
  ppos: menupos_t;
  offs: integer;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_LIG', false);

  ppos := M_WriteText(OptionsLightmapDef.x, OptionsLightmapDef.y + OptionsLightmapDef.itemheight * Ord(ol_accuracy), 'Accuracy: ');
  M_WriteColorText(ppos.x, ppos.y, str_lightmapaccuracymodes[lightmapaccuracymode mod 4], 'CRGRAY');

  lightmapcolorintensityidx := (lightmapcolorintensity - 32) div 8;
  offs := M_StringWidth(OptionsLightmapMenu[Ord(ol_colorintensity)].name + ' ');
  M_DrawThermo(
    (OptionsLightmapDef.x + offs) and not 7, OptionsLightmapDef.y + OptionsLightmapDef.itemheight * Ord(ol_colorintensity), (MAXLMCOLORSENSITIVITY - MINLMCOLORSENSITIVITY) div 8 + 1, lightmapcolorintensityidx);

  offs := M_StringWidth(OptionsLightmapMenu[Ord(ol_lightwidthfactor)].name + ' ');
  M_DrawThermo(
    (OptionsLightmapDef.x + offs) and not 7, OptionsLightmapDef.y + OptionsLightmapDef.itemheight * Ord(ol_lightwidthfactor), MAXLIGHTWIDTHFACTOR + 1, lightwidthfactor);
end;

procedure M_SwitchMirrorMode(choice: integer);
begin
  mirrormode := (mirrormode + 1) mod 4;
end;

const
  str_mirrormodes: array[0..3] of string =
    ('NONE', 'ENVIROMENT', 'WEAPON', 'ALL');

procedure M_DrawOptionsDisplayAdvanced;
var
  ppos: menupos_t;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_ADV', false);

  ppos := M_WriteText(OptionsDisplayAdvancedDef.x, OptionsDisplayAdvancedDef.y + OptionsDisplayAdvancedDef.itemheight * Ord(od_mirror), 'Mirror Mode: ');
  M_WriteColorText(ppos.x, ppos.y, str_mirrormodes[mirrormode mod 4], 'CRGRAY');
end;

procedure M_SwitchGrayscaleMode(choice: integer);
begin
  grayscalemode := (grayscalemode + 1) mod 5;
end;

const
  str_grayscalemodes: array[0..4] of string =
    ('OFF', 'AVERAGE', 'HUMAN PERCIEVE', 'LUMA', 'DESATURATION');

procedure M_SwitchColorsSubsampling(choice: integer);
begin
  colorsubsamplingmode := (colorsubsamplingmode + 1) mod 5;
end;

const
  str_colorsubsamplingmodes: array[0..4] of string =
    ('OFF', '4-4-4 RGB', '3-3-3 RGB', '2-2-2 RGB', '27 COLORS');

procedure M_DrawOptionsDisplayColors;
var
  ppos: menupos_t;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_COL', false);

  ppos := M_WriteText(OptionsDisplayColorsDef.x, OptionsDisplayColorsDef.y + OptionsDisplayColorsDef.itemheight * Ord(oc_grayscale), 'Grayscale Mode: ');
  M_WriteColorText(ppos.x, ppos.y, str_grayscalemodes[grayscalemode mod 5], 'CRGRAY');

  ppos := M_WriteText(OptionsDisplayColorsDef.x, OptionsDisplayColorsDef.y + OptionsDisplayColorsDef.itemheight * Ord(oc_colorsubsubling), 'Palette reduction: ');
  M_WriteColorText(ppos.x, ppos.y, str_colorsubsamplingmodes[colorsubsamplingmode mod 5], 'CRGRAY');
end;

procedure M_DrawOptionsDisplay32bit;
var
  ppos: menupos_t;
begin
  M_DrawDisplayOptions;
  V_DrawPatch(20, 48, SCN_TMP, 'MENU_32B', false);

  ppos := M_WriteText(OptionsDisplay32bitDef.x, OptionsDisplay32bitDef.y + OptionsDisplay32bitDef.itemheight * Ord(od_flatfiltering),
    'Flat filtering: ');
  M_WriteColorText(ppos.x, ppos.y, flatfilteringstrings[extremeflatfiltering], 'CRGRAY');
end;

procedure M_Options(choice: integer);
begin
  M_SetupNextMenu(@OptionsDef);
end;

//
//      Toggle messages on/off
//
procedure M_ChangeMessages(choice: integer);
begin
  showMessages := 1 - showMessages;

  if showMessages = 0 then
    players[consoleplayer]._message := MSGOFF
  else
    players[consoleplayer]._message := MSGON;

  message_dontfuckwithme := true;
end;

//
// M_EndGame
//
procedure M_EndGameResponse(ch: integer);
begin
  if ch <> Ord('y') then
    exit;

  currentMenu.lastOn := itemOn;
  M_ClearMenus;
  D_StartTitle;
end;

procedure M_CmdEndGame;
begin
  if not usergame then
  begin
    S_StartSound(nil, Ord(sfx_oof));
    exit;
  end;

  if netgame then
  begin
    M_StartMessage(NETEND + #13#10 + PRESSKEY, nil, false);
    exit;
  end;

  M_StartMessage(SENDGAME + #13#10 + PRESSYN, @M_EndGameResponse, true);
  C_ExecuteCmd('closeconsole', '1');
end;

procedure M_EndGame(choice: integer);
begin
  M_CmdEndGame;
end;

//
// M_ReadThis
//
procedure M_ReadThis(choice: integer);
begin
  M_SetupNextMenu(@ReadDef1);
end;

procedure M_ReadThis2(choice: integer);
begin
  M_SetupNextMenu(@ReadDef2);
end;

procedure M_FinishReadThis(choice: integer);
begin
  M_SetupNextMenu(@MainDef);
end;

//
// M_QuitDOOM
//
const
  quitsounds: array[0..7] of integer = (
    Ord(sfx_pldeth),
    Ord(sfx_dmpain),
    Ord(sfx_popain),
    Ord(sfx_slop),
    Ord(sfx_telept),
    Ord(sfx_posit1),
    Ord(sfx_posit3),
    Ord(sfx_sgtatk)
  );

  quitsounds2: array[0..7] of integer = (
    Ord(sfx_vilact),
    Ord(sfx_getpow),
    Ord(sfx_boscub),
    Ord(sfx_slop),
    Ord(sfx_skeswg),
    Ord(sfx_kntdth),
    Ord(sfx_bspact),
    Ord(sfx_sgtatk)
  );

procedure M_CmdQuit;
begin
  if not netgame then
  begin
    if gamemode = commercial then
      S_StartSound(nil, quitsounds2[_SHR(gametic, 2) and 7])
    else
      S_StartSound(nil, quitsounds[_SHR(gametic, 2) and 7]);
    I_WaitVBL(1000);
  end;
  G_Quit;
end;


procedure M_QuitResponse(ch: integer);
begin
  if ch <> Ord('y') then
    exit;

  M_CmdQuit;
end;

procedure M_QuitDOOM(choice: integer);
begin
  // We pick index 0 which is language sensitive,
  //  or one at random, between 1 and maximum number.
  if language <> english then
    sprintf(endstring, '%s'#13#10#13#10 + DOSY, [endmsg[0]])
  else
    sprintf(endstring,'%s'#13#10#13#10 + DOSY, [endmsg[(gametic mod (NUM_QUITMESSAGES - 2)) + 1]]);

  M_StartMessage(endstring, @M_QuitResponse, true);
end;

procedure M_ChangeSensitivity(choice: integer);
begin
  case choice of
    0:
      if mouseSensitivity > 0 then
        dec(mouseSensitivity);
    1:
      if mouseSensitivity < 19 then
        inc(mouseSensitivity);
  end;
end;

procedure M_ChangeSensitivityX(choice: integer);
begin
  case choice of
    0:
      if mouseSensitivityX > 0 then
        dec(mouseSensitivityX);
    1:
      if mouseSensitivityX < 10 then
        inc(mouseSensitivityX);
  end;
end;

procedure M_ChangeSensitivityY(choice: integer);
begin
  case choice of
    0:
      if mouseSensitivityY > 0 then
        dec(mouseSensitivityY);
    1:
      if mouseSensitivityY < 10 then
        inc(mouseSensitivityY);
  end;
end;


procedure M_ChangeDetail(choice: integer);
begin
  detailLevel := (detailLevel + 1) mod DL_NUMRESOLUTIONS;

  R_SetViewSize;

  case detailLevel of
    DL_MEDIUM:
      players[consoleplayer]._message := DETAILMED;
    DL_NORMAL:
      players[consoleplayer]._message := DETAILNORM;
  end;

end;

procedure M_ChangeScreenSize(choice: integer);
begin
  case choice of
    0:
      if mdisplaymode_idx > 0 then
        dec(mdisplaymode_idx);
    1:
      if mdisplaymode_idx < numdisplaymodes - 1 then
        inc(mdisplaymode_idx);
  end;
end;

procedure M_ApplyScreenSize(choice: integer);
begin
  if mdisplaymode_idx < 0 then
    mdisplaymode_idx := 0
  else if mdisplaymode_idx >= numdisplaymodes then
    mdisplaymode_idx := numdisplaymodes - 1;

  V_SetScreenResolution(displaymodes[mdisplaymode_idx].width, displaymodes[mdisplaymode_idx].height);
end;

procedure M_ChangeFlatFiltering(choice: integer);
begin
  C_ExecuteCmd('extremeflatfiltering', yesnoStrings[not extremeflatfiltering]);
end;

procedure M_BoolCmd(choice: integer);
var
  s: string;
begin
  s := currentMenu.menuitems[choice].cmd;
  if length(s) = 0 then
    I_Error('M_BoolCmd(): Unknown option');
  C_ExecuteCmd(s, yesnoStrings[not currentMenu.menuitems[choice].pBoolVal^]);
end;

procedure M_SizeDisplay(choice: integer);
begin
  case choice of
    0:
      begin
        if m_screensize > 0 then
        begin
          dec(screenblocks);
          dec(m_screensize);
        end;
      end;
    1:
      begin
        if m_screensize < 8 then
        begin
          inc(screenblocks);
          inc(m_screensize);
        end;
      end;
  end;

  R_SetViewSize;
end;

//
// CONTROL PANEL
//

//
// M_Responder
//
var
  joywait: integer;
  mousewait: integer;
  mmousex: integer;
  mmousey: integer;
  mlastx: integer;
  mlasty: integer;
  m_altdown: boolean = false;

function M_Responder(ev: Pevent_t): boolean;
var
  ch: integer;
  i: integer;
  palette: PByteArray;
begin
  if (ev.data1 = KEY_RALT) or (ev.data1 = KEY_LALT) then
  begin
    m_altdown := ev._type = ev_keydown;
    result := false;
    exit;
  end;

  ch := -1;

  if (ev._type = ev_joystick) and (joywait < I_GetTime) then
  begin
    if ev.data3 < 0 then
    begin
      ch := KEY_UPARROW;
      joywait := I_GetTime + 5;
    end
    else if ev.data3 > 0 then
    begin
      ch := KEY_DOWNARROW;
      joywait := I_GetTime + 5;
    end;

    if ev.data2 < 0 then
    begin
      ch := KEY_LEFTARROW;
      joywait := I_GetTime + 2;
    end
    else if ev.data2 > 0 then
    begin
      ch := KEY_RIGHTARROW;
      joywait := I_GetTime + 2;
    end;

    if ev.data1 and 1 <> 0 then
    begin
      ch := KEY_ENTER;
      joywait := I_GetTime + 5;
    end;
    if ev.data1 and 2 <> 0 then
    begin
      ch := KEY_BACKSPACE;
      joywait := I_GetTime + 5;
    end;
  end
  else if (ev._type = ev_mouse) and (mousewait < I_GetTime) then
  begin
    mmousey := mmousey + ev.data3;
    if mmousey < mlasty - 30 then
    begin
      ch := KEY_DOWNARROW;
      mousewait := I_GetTime + 5;
      mlasty := mlasty - 30;
      mmousey := mlasty;
    end
    else if mmousey > mlasty + 30 then
    begin
      ch := KEY_UPARROW;
      mousewait := I_GetTime + 5;
      mlasty := mlasty + 30;
      mmousey := mlasty;
    end;

    mmousex := mmousex + ev.data2;
    if mmousex < mlastx - 30 then
    begin
      ch := KEY_LEFTARROW;
      mousewait := I_GetTime + 5;
      mlastx := mlastx - 30;
      mmousex := mlastx;
    end
    else if mmousex > mlastx + 30 then
    begin
      ch := KEY_RIGHTARROW;
      mousewait := I_GetTime + 5;
      mlastx := mlastx + 30;
      mmousex := mlastx;
    end;

    if ev.data1 and 1 <> 0 then
    begin
      ch := KEY_ENTER;
      mousewait := I_GetTime + 15;
    end;

    if ev.data1 and 2 <> 0 then
    begin
      ch := KEY_BACKSPACE;
      mousewait := I_GetTime + 15;
    end
  end
  else if ev._type = ev_keydown then
    ch := ev.data1;

  if ch = -1 then
  begin
    result := false;
    exit;
  end;

  // Save Game string input
  if saveStringEnter then
  begin
    case ch of
      KEY_BACKSPACE:
        begin
          if saveCharIndex > 0 then
          begin
            dec(saveCharIndex);
            SetLength(savegamestrings[saveSlot], saveCharIndex);
          end;
        end;
      KEY_ESCAPE:
        begin
          saveStringEnter := false;
          savegamestrings[saveSlot] := saveOldString;
        end;
      KEY_ENTER:
        begin
          saveStringEnter := false;
          if savegamestrings[saveSlot] <> '' then
            M_DoSave(saveSlot);
        end
    else
      begin
        ch := Ord(toupper(Chr(ch)));
        if ch <> 32 then
        if (ch - Ord(HU_FONTSTART) < 0) or (ch - Ord(HU_FONTSTART) >= HU_FONTSIZE) then
        else
        begin
          if (ch >= 32) and (ch <= 127) and
             (saveCharIndex < SAVESTRINGSIZE - 1) and
             (M_StringWidth(savegamestrings[saveSlot]) < (SAVESTRINGSIZE - 2) * 8) then
          begin
            inc(saveCharIndex);
            savegamestrings[saveSlot] := savegamestrings[saveSlot] + Chr(ch);
          end;
        end;
      end;
    end;
    result := true;
    exit;
  end;

  // Key bindings
  if bindkeyEnter then
  begin
    case ch of
      KEY_ESCAPE:
        begin
          bindkeyEnter := false;
          KeyBindingsInfo[bindkeySlot].pkey^ := saveOldkey;
        end;
      KEY_ENTER:
        begin
          bindkeyEnter := false;
        end;
    else
      M_SetKeyBinding(bindkeySlot, ch);
      bindkeyEnter := false;
    end;
    result := true;
    exit;
  end;

  // Take care of any messages that need input
  if messageToPrint <> 0 then
  begin
    if messageNeedsInput and ( not(
      (ch = Ord(' ')) or (ch = Ord('n')) or (ch = Ord('y')) or (ch = KEY_ESCAPE))) then
    begin
      result := false;
      exit;
    end;

    menuactive := messageLastMenuActive;
    messageToPrint := 0;
    if Assigned(messageRoutine) then
      messageRoutine(ch);

    result := true;

    if I_GameFinished then
      exit;

    menuactive := false;
    M_SwtchxSound;
    exit;
  end;

  // F-Keys
  if not menuactive then
    case ch of
      KEY_MINUS:    // Screen size down
        begin
          if (amstate = am_only) or chat_on then
          begin
            result := false;
            exit;
          end;
          M_SizeDisplay(0);
          S_StartSound(nil, Ord(sfx_stnmov));
          result := true;
          exit;
        end;
      KEY_EQUALS, Ord('+'):   // Screen size up
        begin
          if (amstate = am_only) or chat_on then
          begin
            result := false;
            exit;
          end;
          M_SizeDisplay(1);
          S_StartSound(nil, Ord(sfx_stnmov));
          result := true;
          exit;
        end;
      KEY_F1:      // Help key
        begin
          M_StartControlPanel;
          if gamemode = retail then
            currentMenu := @ReadDef2
          else
            currentMenu := @ReadDef1;

          itemOn := 0;
          M_SwtchnSound;
          result := true;
          exit;
        end;
      KEY_F2:  // Save
        begin
          M_StartControlPanel;
          M_SwtchnSound;
          M_SaveGame(0);
          result := true;
          exit;
        end;
      KEY_F3:  // Load
        begin
          M_StartControlPanel;
          M_SwtchnSound;
          M_LoadGame(0);
          result := true;
          exit;
        end;
      KEY_F4:   // Sound Volume
        begin
          M_StartControlPanel;
          currentMenu := @SoundVolDef;
          itemOn := Ord(sfx_vol);
          M_SwtchnSound;
          result := true;
          exit;
        end;
      KEY_F5:   // Detail toggle
        begin
          M_ChangeDetail(0);
          M_SwtchnSound;
          result := true;
          exit;
        end;
      KEY_F6:   // Quicksave
        begin
          M_SwtchnSound;
          M_QuickSave;
          result := true;
          exit;
        end;
      KEY_F7:   // End game
        begin
          M_SwtchnSound;
          M_EndGame(0);
          result := true;
          exit;
        end;
      KEY_F8:   // Toggle messages
        begin
          M_ChangeMessages(0);
          M_SwtchnSound;
          result := true;
          exit;
        end;
      KEY_F9:   // Quickload
        begin
          M_SwtchnSound;
          M_QuickLoad;
          result := true;
          exit;
        end;
      KEY_F10:  // Quit DOOM
        begin
          M_SwtchnSound;
          M_QuitDOOM(0);
          result := true;
          exit;
        end;
      KEY_F11:  // gamma toggle
        begin
          inc(usegamma);
          if usegamma >= GAMMASIZE then
            usegamma := 0;
          players[consoleplayer]._message := gammamsg[usegamma];
          palette := V_ReadPalette(PU_STATIC);
          I_SetPalette(palette);
          V_SetPalette(palette);
          Z_ChangeTag(palette, PU_CACHE);
          result := true;
          exit;
        end;
      KEY_ENTER:
        begin
          if m_altdown then
          begin
            I_ChangeFullScreen;
            mousewait := I_GetTime + 15;
            result := true;
            exit;
          end;
        end;
    end;

  // Pop-up menu?
  if not menuactive then
  begin
    if ch = KEY_ESCAPE then
    begin
      M_StartControlPanel;
      M_SwtchnSound;
      result := true;
      exit;
    end;
    result := false;
    exit;
  end;

  // Keys usable within menu
  case ch of
    KEY_PAGEUP:
      begin
        itemOn := -1;
        repeat
          inc(itemOn);
          S_StartSound(nil, Ord(sfx_pstop));
        until currentMenu.menuitems[itemOn].status <> -1;
        result := true;
        exit;
      end;
    KEY_PAGEDOWN:
      begin
        itemOn := currentMenu.numitems;
        repeat
          dec(itemOn);
          S_StartSound(nil, Ord(sfx_pstop));
        until currentMenu.menuitems[itemOn].status <> -1;
        result := true;
        exit;
      end;
    KEY_DOWNARROW:
      begin
        repeat
          if itemOn + 1 > currentMenu.numitems - 1 then
            itemOn := 0
          else
            inc(itemOn);
          S_StartSound(nil, Ord(sfx_pstop));
        until currentMenu.menuitems[itemOn].status <> -1;
        result := true;
        exit;
      end;
    KEY_UPARROW:
      begin
        repeat
          if itemOn = 0 then
            itemOn := currentMenu.numitems - 1
          else
            dec(itemOn);
          S_StartSound(nil, Ord(sfx_pstop));
        until currentMenu.menuitems[itemOn].status <> -1;
        result := true;
        exit;
      end;
    KEY_LEFTARROW:
      begin
        if Assigned(currentMenu.menuitems[itemOn].routine) and
          (currentMenu.menuitems[itemOn].status = 2) then
        begin
          S_StartSound(nil, Ord(sfx_stnmov));
          currentMenu.menuitems[itemOn].routine(0);
        end
        else if (currentMenu.leftMenu <> nil) and not (ev._type in [ev_mouse, ev_joystick]) then
        begin
          currentMenu.lastOn := itemOn;
          currentMenu := currentMenu.leftMenu;
          itemOn := currentMenu.lastOn;
          M_SwtchnSound;
        end;
        result := true;
        exit;
      end;
    KEY_RIGHTARROW:
      begin
        if Assigned(currentMenu.menuitems[itemOn].routine) and
          (currentMenu.menuitems[itemOn].status = 2) then
        begin
          S_StartSound(nil, Ord(sfx_stnmov));
          currentMenu.menuitems[itemOn].routine(1);
        end
        else if (currentMenu.rightMenu <> nil) and not (ev._type in [ev_mouse, ev_joystick]) then
        begin
          currentMenu.lastOn := itemOn;
          currentMenu := currentMenu.rightMenu;
          itemOn := currentMenu.lastOn;
          M_SwtchnSound;
        end;
        result := true;
        exit;
      end;
    KEY_ENTER:
      begin
        if Assigned(currentMenu.menuitems[itemOn].routine) and
          (currentMenu.menuitems[itemOn].status <> 0) then
        begin
          currentMenu.lastOn := itemOn;
          if currentMenu.menuitems[itemOn].status = 2 then
          begin
            currentMenu.menuitems[itemOn].routine(1); // right arrow
            S_StartSound(nil, Ord(sfx_stnmov));
          end
          else
          begin
            currentMenu.menuitems[itemOn].routine(itemOn);
            S_StartSound(nil, Ord(sfx_pistol));
          end;
        end;
        result := true;
        exit;
      end;
    KEY_ESCAPE:
      begin
        currentMenu.lastOn := itemOn;
        M_ClearMenus;
        M_SwtchxSound;
        result := true;
        exit;
      end;
    KEY_BACKSPACE:
      begin
        currentMenu.lastOn := itemOn;
        if currentMenu.prevMenu <> nil then
        begin
          currentMenu := currentMenu.prevMenu;
          itemOn := currentMenu.lastOn;
          M_SwtchnSound;
        end;
        result := true;
        exit;
      end;
  else
    begin
      for i := itemOn + 1 to currentMenu.numitems - 1 do
        if currentMenu.menuitems[i].alphaKey = Chr(ch) then
        begin
          itemOn := i;
          S_StartSound(nil, Ord(sfx_pstop));
          result := true;
          exit;
        end;
      for i := 0 to itemOn do
        if currentMenu.menuitems[i].alphaKey = Chr(ch) then
        begin
          itemOn := i;
          S_StartSound(nil, Ord(sfx_pstop));
          result := true;
          exit;
        end;
    end;
  end;

  result := false;
end;

//
// M_StartControlPanel
//
procedure M_StartControlPanel;
begin
  // intro might call this repeatedly
  if menuactive then
    exit;

  menuactive := true;
  currentMenu := @MainDef;// JDC
  itemOn := currentMenu.lastOn; // JDC
end;

//
// M_Ticker
//
procedure M_Ticker;
begin
  dec(skullAnimCounter);
  if skullAnimCounter <= 0 then
  begin
    whichSkull := whichSkull xor 1;
    skullAnimCounter := 8;
  end;
end;

procedure M_CmdSetupNextMenu(menudef: Pmenu_t);
begin
  menuactive := true;
  if (menudef = @LoadDef) or (menudef = @SaveDef) then
    M_ReadSaveStrings;
  M_SetupNextMenu(menudef);
  C_ExecuteCmd('closeconsole');
end;

procedure M_CmdMenuMainDef;
begin
  M_CmdSetupNextMenu(@MainDef);
end;

procedure M_CmdMenuNewDef;
begin
  M_CmdSetupNextMenu(@NewDef);
end;

procedure M_CmdMenuOptionsDef;
begin
  M_CmdSetupNextMenu(@OptionsDef);
end;

procedure M_CmdMenuOptionsGeneralDef;
begin
  M_CmdSetupNextMenu(@OptionsGeneralDef);
end;

procedure M_CmdMenuOptionsDisplayDef;
begin
  M_CmdSetupNextMenu(@OptionsDisplayDef);
end;

procedure M_CmdMenuOptionsDisplayDetailDef;
begin
  M_CmdSetupNextMenu(@OptionsDisplayDetailDef);
end;

procedure M_CmdMenuOptionsDisplayAppearanceDef;
begin
  M_CmdSetupNextMenu(@OptionsDisplayAppearanceDef);
end;

procedure M_CmdMenuOptionsDisplayAdvancedDef;
begin
  M_CmdSetupNextMenu(@OptionsDisplayAdvancedDef);
end;

procedure M_CmdMenuOptionsDisplay32bitDef;
begin
  M_CmdSetupNextMenu(@OptionsDisplay32bitDef);
end;

procedure M_CmdMenuSoundDef;
begin
  M_CmdSetupNextMenu(@SoundDef);
end;

procedure M_CmdMenuSoundVolDef;
begin
  M_CmdSetupNextMenu(@SoundVolDef);
end;

procedure M_CmdMenuCompatibilityDef;
begin
  M_CmdSetupNextMenu(@CompatibilityDef);
end;

procedure M_CmdMenuControlsDef;
begin
  M_CmdSetupNextMenu(@ControlsDef);
end;

procedure M_CmdMenuSystemDef;
begin
  M_CmdSetupNextMenu(@SystemDef);
end;

procedure M_CmdMenuLoadDef;
begin
  M_CmdSetupNextMenu(@LoadDef);
end;

procedure M_CmdMenuSaveDef;
begin
  M_CmdSetupNextMenu(@SaveDef);
end;

//
// M_Init
//
procedure M_Init;
begin
  currentMenu := @MainDef;
  menuactive := false;
  itemOn := currentMenu.lastOn;
  whichSkull := 0;
  skullAnimCounter := 10;
  m_screensize := screenblocks - 4;
  messageToPrint := 0;
  messageString := '';
  messageLastMenuActive := menuactive;
  quickSaveSlot := -1;

  // Here we could catch other version dependencies,
  //  like HELP1/2, and four episodes.

  case gamemode of
    commercial:
      begin
        // This is used because DOOM 2 had only one HELP
        //  page. I use CREDIT as second page now, but
        //  kept this hack for educational purposes.
        MainMenu[Ord(mm_readthis)] := MainMenu[Ord(mm_quitdoom)];
        dec(MainDef.numitems);
        MainDef.y := MainDef.y + 8;
        NewDef.prevMenu := @MainDef;
        ReadDef1.drawproc := M_DrawReadThis1;
        ReadDef1.x := 330;
        ReadDef1.y := 165;
        ReadMenu1[0].routine := @M_FinishReadThis;
      end;
    shareware:
      begin
        ReadDef2.x := 280;
        ReadDef2.y := 185; // x,y of menu
        // We need to remove the fourth episode.
        // Episode 2 and 3 are handled,
        // branching to an ad screen.
        dec(EpiDef.numitems);
      end;
    registered:
      begin
        // We need to remove the fourth episode.
        dec(EpiDef.numitems);
      end;
  end;

  C_AddCmd('keyboardmode', @M_CmdKeyboardMode);
  C_AddCmd('exit, quit', @M_CmdQuit);
  C_AddCmd('halt', @I_Quit);
  C_AddCmd('set', @Cmd_Set);
  C_AddCmd('get', @Cmd_Get);
  C_AddCmd('typeof', @Cmd_TypeOf);
  C_AddCmd('endgame', @M_CmdEndGame);
  C_AddCmd('defaults, setdefaults', @M_SetDefaults);
  C_AddCmd('default, setdefault', @M_SetDefaults);
  C_AddCmd('menu_main', @M_CmdMenuMainDef);
  C_AddCmd('menu_newgame, menu_new', @M_CmdMenuNewDef);
  C_AddCmd('menu_options', @M_CmdMenuOptionsDef);
  C_AddCmd('menu_optionsgeneral, menu_generaloptions', @M_CmdMenuOptionsGeneralDef);
  C_AddCmd('menu_optionsdisplay, menu_displayoptions, menu_display', @M_CmdMenuOptionsDisplayDef);
  C_AddCmd('menu_optionsdisplayappearence, menu_displayappearenceoptions, menu_displayappearence', @M_CmdMenuOptionsDisplayAppearanceDef);
  C_AddCmd('menu_optionsdisplayadvanced, menu_displayadvancedoptions, menu_displayadvanced', @M_CmdMenuOptionsDisplayAdvancedDef);
  C_AddCmd('menu_optionsdisplay32bit, menu_display32bitoptions, menu_display32bit', @M_CmdMenuOptionsDisplay32bitDef);
  C_AddCmd('menu_optionsdisplaydetail, menu_displaydetailoptions', @M_CmdMenuOptionsDisplayDetailDef);
  C_AddCmd('menu_optionssound, menu_soundoptions, menu_sound', @M_CmdMenuSoundDef);
  C_AddCmd('menu_optionssoundvol, menu_soundvoloptions, menu_soundvol', @M_CmdMenuSoundVolDef);
  C_AddCmd('menu_optionscompatibility, menu_compatibilityoptions, menu_compatibility', @M_CmdMenuCompatibilityDef);
  C_AddCmd('menu_optionscontrols, menu_controlsoptions, menu_controls', @M_CmdMenuControlsDef);
  C_AddCmd('menu_optionssystem, menu_systemoptions, menu_system', @M_CmdMenuSystemDef);
  C_AddCmd('menu_load, menu_loadgame', @M_CmdMenuLoadDef);
  C_AddCmd('menu_save, menu_savegame', @M_CmdMenuSaveDef);
end;

//
// JVAL
// Shade menu background
//
procedure M_MenuShader;
begin
  shademenubackground := shademenubackground mod 3;
  if (not wipedisplay) and (shademenubackground >= 1) then
    V_ShadeScreen(SCN_FG);
end;

procedure M_FinishUpdate(const height: integer);
begin
  // JVAL
  // Menu is no longer drawn to primary surface,
  // Instead we use SCN_TMP and after the drawing we blit to primary surface
  if inhelpscreens then
  begin
    V_CopyRectTransparent(0, 0, SCN_TMP, 320, 200, 0, 0, SCN_FG, true);
    inhelpscreens := false;
  end
  else
  begin
    M_MenuShader;
    V_CopyRectTransparent(0, 0, SCN_TMP, 320, height, 0, 0, SCN_FG, true);
  end;
end;

procedure M_DrawFlatBackground(const sflat: string);
var
  x, y: integer;
  src: PByteArray;
  dest: integer;
  iflat: integer;
begin
  iflat := R_FlatNumForName(sflat);
  if iflat < 0 then
  begin
    iflat := R_FlatNumForName(DEFMENUBACKGROUNDFLAT);
    if iflat < 0 then
      exit;
  end;

  src := W_CacheLumpNum(R_GetLumpForFlat(iflat), PU_STATIC);
  dest := 0;

  for y := 0 to 200 - 1 do
  begin
    for x := 0 to (320 div 64) - 1 do
    begin
      memcpy(@screens[SCN_TMP, dest], @src[_SHL(y and 63, 6)], 64);
      dest := dest + 64;
    end;

    if 320 and 63 <> 0 then
    begin
      memcpy(@screens[SCN_TMP, dest], @src[_SHL(y and 63, 6)], 320 and 63);
      dest := dest + (320 and 63);
    end;
  end;
  Z_ChangeTag(src, PU_CACHE);
end;

//
// M_Drawer
// Called after the view has been rendered,
// but before it has been blitted.
//

procedure M_Drawer;
var
  i: integer;
  str: string;
  len: integer;
  x, y: integer;
  mheight: integer;
  ppos: menupos_t;
  rstr: string;
  rlen: integer;
begin
  // Horiz. & Vertically center string and print it.
  if messageToPrint <> 0 then
  begin

    mheight := M_StringHeight(messageString);
    y := (200 - mheight) div 2;
    mheight := y + mheight + 20;
    ZeroMemory(screens[SCN_TMP], 320 * mheight);
    len := Length(messageString);
    str := '';
    for i := 1 to len do
    begin
      if messageString[i] = #13 then
        y := y + hu_font[0].height
      else if messageString[i] = #10 then
      begin
        x := (320 - M_StringWidth(str)) div 2;
        M_WriteText(x, y, str);
        str := '';
      end
      else
        str := str + messageString[i];
    end;
    if str <> '' then
    begin
      x := (320 - M_StringWidth(str)) div 2;
      y := y + hu_font[0].height;
      M_WriteText(x, y, str);
    end;

    M_FinishUpdate(mheight);
    exit;
  end;

  if not menuactive then
    exit;

  ZeroMemory(screens[SCN_TMP], 320 * 200);

  if (shademenubackground = 2) and currentMenu.texturebk then
    M_DrawFlatBackground(menubackgroundflat);

  if Assigned(currentMenu.drawproc) then
    currentMenu.drawproc; // call Draw routine

  // DRAW MENU
  x := currentMenu.x;
  y := currentMenu.y;

  for i := 0 to currentMenu.numitems - 1 do
  begin
    str := currentMenu.menuitems[i].name;
    if str <> '' then
    begin
      if str[1] = '!' then // Draw text with Yes/No
      begin
        delete(str, 1, 1);
        if currentMenu.menuitems[i].pBoolVal <> nil then
        begin
          ppos := M_WriteText(x, y, str + ': ');
          M_WriteColorText(ppos.x, ppos.y, yesnoStrings[currentMenu.menuitems[i].pBoolVal^], 'CRGRAY');
        end
        else
          M_WriteText(x, y, str);
      end
      else
        V_DrawPatch(x, y, SCN_TMP,
          currentMenu.menuitems[i].name, false);
    end;
    y := y + currentMenu.itemheight;
  end;

  if currentMenu.leftMenu <> nil then
    M_WriteColorText(20, 158, '<--' + currentMenu.leftMenu.title, 'CRTAN');

  if currentMenu.rightMenu <> nil then
  begin
    rstr := currentMenu.rightMenu.title + '-->';
    rlen := M_StringWidth(rstr);
    M_WriteColorText(300 - rlen, 158, rstr, 'CRTAN');
  end;

  if currentMenu.itemheight > LINEHEIGHT2 then
    // DRAW SKULL
    V_DrawPatch(x + SKULLXOFF, currentMenu.y + SKULLYOFF + itemOn * currentMenu.itemheight, SCN_TMP,
      skullName[whichSkull], false)
  else
    M_WriteColorText(x + ARROWXOFF, currentMenu.y + itemOn * currentMenu.itemheight, '-',  'CRGRAY');

  M_FinishUpdate(200);
end;


procedure M_InitMenus;
var
  i: integer;
  pmi: Pmenuitem_t;
begin
////////////////////////////////////////////////////////////////////////////////
//gammamsg
  gammamsg[0] := GAMMALVL0;
  gammamsg[1] := GAMMALVL1;
  gammamsg[2] := GAMMALVL2;
  gammamsg[3] := GAMMALVL3;
  gammamsg[4] := GAMMALVL4;

////////////////////////////////////////////////////////////////////////////////
//skullName
  skullName[0] := 'M_SKULL1';
  skullName[1] := 'M_SKULL2';

////////////////////////////////////////////////////////////////////////////////
// MainMenu
  pmi := @MainMenu[0];
  pmi.status := 1;
  pmi.name := 'M_NGAME';
  pmi.cmd := '';
  pmi.routine := @M_NewGame;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'n';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_OPTION';
  pmi.cmd := '';
  pmi.routine := @M_Options;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'o';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_LOADG';
  pmi.cmd := '';
  pmi.routine := @M_LoadGame;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'l';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_SAVEG';
  pmi.cmd := '';
  pmi.routine := @M_SaveGame;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  // Another hickup with Special edition.
  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_RDTHIS';
  pmi.cmd := '';
  pmi.routine := @M_ReadThis;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'r';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_QUITG';
  pmi.cmd := '';
  pmi.routine := @M_QuitDOOM;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'q';

////////////////////////////////////////////////////////////////////////////////
//MainDef
  MainDef.title := 'Main';
  MainDef.numitems := Ord(main_end);
  MainDef.prevMenu := nil;
  MainDef.menuitems := Pmenuitem_tArray(@MainMenu);
  MainDef.drawproc := @M_DrawMainMenu;  // draw routine
  MainDef.x := 97;
  MainDef.y := 64;
  MainDef.lastOn := 0;
  MainDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//EpisodeMenu
  pmi := @EpisodeMenu[0];
  pmi.status := 1;
  pmi.name := 'M_EPI1';
  pmi.cmd := '';
  pmi.routine := @M_Episode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'k';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_EPI2';
  pmi.cmd := '';
  pmi.routine := @M_Episode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 't';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_EPI3';
  pmi.cmd := '';
  pmi.routine := @M_Episode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'i';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_EPI4';
  pmi.cmd := '';
  pmi.routine := @M_Episode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 't';

////////////////////////////////////////////////////////////////////////////////
//EpiDef
  EpiDef.title := 'Episode select';
  EpiDef.numitems := Ord(ep_end); // # of menu items
  EpiDef.prevMenu := @MainDef; // previous menu
  EpiDef.menuitems := Pmenuitem_tArray(@EpisodeMenu);  // menu items
  EpiDef.drawproc := @M_DrawEpisode;  // draw routine
  EpiDef.x := 48;
  EpiDef.y := 63; // x,y of menu
  EpiDef.lastOn := Ord(ep1); // last item user was on in menu
  EpiDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//NewGameMenu
  pmi := @NewGameMenu[0];
  pmi.status := 1;
  pmi.name := 'M_JKILL';
  pmi.cmd := '';
  pmi.routine := @M_ChooseSkill;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'i';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_ROUGH';
  pmi.cmd := '';
  pmi.routine := @M_ChooseSkill;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'h';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_HURT';
  pmi.cmd := '';
  pmi.routine := @M_ChooseSkill;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'h';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_ULTRA';
  pmi.cmd := '';
  pmi.routine := @M_ChooseSkill;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'u';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_NMARE';
  pmi.cmd := '';
  pmi.routine := @M_ChooseSkill;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'n';

////////////////////////////////////////////////////////////////////////////////
//NewDef
  NewDef.title := 'New game';
  NewDef.numitems := Ord(newg_end); // # of menu items
  NewDef.prevMenu := @EpiDef; // previous menu
  NewDef.menuitems := Pmenuitem_tArray(@NewGameMenu);  // menu items
  NewDef.drawproc := @M_DrawNewGame;  // draw routine
  NewDef.x := 48;
  NewDef.y := 63; // x,y of menu
  NewDef.lastOn := Ord(hurtme); // last item user was on in menu
  NewDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//OptionsMenu
  pmi := @OptionsMenu[0];
  pmi.status := 1;
  pmi.name := 'MENU_GEN';
  pmi.cmd := '';
  pmi.routine := @M_OptionsGeneral;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'g';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_DIS';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplay;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'd';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_SOU';
  pmi.cmd := '';
  pmi.routine := @M_OptionsSound;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_COM';
  pmi.cmd := '';
  pmi.routine := @M_OptionsCompatibility;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_CON';
  pmi.cmd := '';
  pmi.routine := @M_OptionsConrols;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'r';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_SYS';
  pmi.cmd := '';
  pmi.routine := @M_OptionsSystem;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'y';

////////////////////////////////////////////////////////////////////////////////
//OptionsDef
  OptionsDef.title := 'Options';
  OptionsDef.numitems := Ord(opt_end); // # of menu items
  OptionsDef.prevMenu := @MainDef; // previous menu
  OptionsDef.menuitems := Pmenuitem_tArray(@OptionsMenu);  // menu items
  OptionsDef.drawproc := @M_DrawOptions;  // draw routine
  OptionsDef.x := 80;
  OptionsDef.y := 48; // x,y of menu
  OptionsDef.lastOn := 0; // last item user was on in menu
  OptionsDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//OptionsGeneralMenu
  pmi := @OptionsGeneralMenu[0];
  pmi.status := 1;
  pmi.name := 'M_ENDGAM';
  pmi.cmd := '';
  pmi.routine := @M_EndGame;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'e';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'M_MESSG';
  pmi.cmd := '';
  pmi.routine := @M_ChangeMessages;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'm';

  inc(pmi);
  pmi.status := 2;
  pmi.name := 'M_SCRNSZ';
  pmi.cmd := '';
  pmi.routine := @M_SizeDisplay;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

////////////////////////////////////////////////////////////////////////////////
//OptionsGeneralDef
  OptionsGeneralDef.title := 'General';
  OptionsGeneralDef.numitems := Ord(optgen_end); // # of menu items
  OptionsGeneralDef.prevMenu := @OptionsDef; // previous menu
  OptionsGeneralDef.menuitems := Pmenuitem_tArray(@OptionsGeneralMenu);  // menu items
  OptionsGeneralDef.drawproc := @M_DrawGeneralOptions;  // draw routine
  OptionsGeneralDef.x := 80;
  OptionsGeneralDef.y := 48; // x,y of menu
  OptionsGeneralDef.lastOn := 0; // last item user was on in menu
  OptionsGeneralDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayMenu
  pmi := @OptionsDisplayMenu[0];
  pmi.status := 1;
  pmi.name := 'MENU_DET';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayDetail;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'd';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_MAP';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayAutomap;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'a';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_APP';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayAppearance;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'a';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_ADV';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayAdvanced;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'v';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_COL';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayColors;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_LIG';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplayLightmap;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'l';

  inc(pmi);
  pmi.status := 1;
  pmi.name := 'MENU_32B';
  pmi.cmd := '';
  pmi.routine := @M_OptionsDisplay32bit;
  pmi.pBoolVal := nil;
  pmi.alphaKey := '3';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayDef
  OptionsDisplayDef.title := 'Display options';
  OptionsDisplayDef.numitems := Ord(optdisp_end); // # of menu items
  OptionsDisplayDef.prevMenu := @OptionsDef; // previous menu
  OptionsDisplayDef.menuitems := Pmenuitem_tArray(@OptionsDisplayMenu);  // menu items
  OptionsDisplayDef.drawproc := @M_DrawDisplayOptions;  // draw routine
  OptionsDisplayDef.x := 80;
  OptionsDisplayDef.y := 48; // x,y of menu
  OptionsDisplayDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayDetailMenu
  pmi := @OptionsDisplayDetailMenu[0];
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_ChangeDetail;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 2;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_ChangeScreenSize;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_ApplyScreenSize;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'a';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayDetailDef
  OptionsDisplayDetailDef.title := 'Detail';
  OptionsDisplayDetailDef.numitems := Ord(optdispdetail_end); // # of menu items
  OptionsDisplayDetailDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplayDetailDef.leftMenu := @OptionsDisplay32bitDef; // left menu
  OptionsDisplayDetailDef.rightMenu := @OptionsDisplayAutomapDef; // right menu
  OptionsDisplayDetailDef.menuitems := Pmenuitem_tArray(@OptionsDisplayDetailMenu);  // menu items
  OptionsDisplayDetailDef.drawproc := @M_DrawDisplayDetailOptions;  // draw routine
  OptionsDisplayDetailDef.x := 32;
  OptionsDisplayDetailDef.y := 68; // x,y of menu
  OptionsDisplayDetailDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayDetailDef.itemheight := LINEHEIGHT2;
  OptionsDisplayDetailDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAutomapMenu
  pmi := @OptionsDisplayAutomapMenu[0];
  pmi.status := 1;
  pmi.name := '!Overlay Automap';
  pmi.cmd := 'allowautomapoverlay';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @allowautomapoverlay;
  pmi.alphaKey := 'o';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Rotate  Automap';
  pmi.cmd := 'allowautomaprotate';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @allowautomaprotate;
  pmi.alphaKey := 'r';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAutomapDef
  OptionsDisplayAutomapDef.title := 'Automap';
  OptionsDisplayAutomapDef.numitems := Ord(optdispautomap_end); // # of menu items
  OptionsDisplayAutomapDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplayAutomapDef.leftMenu := @OptionsDisplayDetailDef; // left menu
  OptionsDisplayAutomapDef.rightMenu := @OptionsDisplayAppearanceDef; // right menu
  OptionsDisplayAutomapDef.menuitems := Pmenuitem_tArray(@OptionsDisplayAutomapMenu);  // menu items
  OptionsDisplayAutomapDef.drawproc := @M_DrawDisplayAutomapOptions;  // draw routine
  OptionsDisplayAutomapDef.x := 32;
  OptionsDisplayAutomapDef.y := 68; // x,y of menu
  OptionsDisplayAutomapDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayAutomapDef.itemheight := LINEHEIGHT2;
  OptionsDisplayAutomapDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAppearanceMenu
  pmi := @OptionsDisplayAppearanceMenu[0];
  pmi.status := 1;
  pmi.name := '!Display fps';
  pmi.cmd := 'drawfps';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @drawfps;
  pmi.alphaKey := 'f';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Menu background';
  pmi.cmd := '';
  pmi.routine := @M_SwitchShadeMode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'b';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Display ENDOOM screen';
  pmi.cmd := 'displayendscreen';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @displayendscreen;
  pmi.alphaKey := 'e';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAppearanceDef
  OptionsDisplayAppearanceDef.title := 'Appearence';
  OptionsDisplayAppearanceDef.numitems := Ord(optdispappearance_end); // # of menu items
  OptionsDisplayAppearanceDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplayAppearanceDef.leftMenu := @OptionsDisplayAutomapDef; // left menu
  OptionsDisplayAppearanceDef.rightMenu := @OptionsDisplayAdvancedDef; // rightmenu
  OptionsDisplayAppearanceDef.menuitems := Pmenuitem_tArray(@OptionsDisplayAppearanceMenu);  // menu items
  OptionsDisplayAppearanceDef.drawproc := @M_DrawDisplayAppearanceOptions;  // draw routine
  OptionsDisplayAppearanceDef.x := 32;
  OptionsDisplayAppearanceDef.y := 68; // x,y of menu
  OptionsDisplayAppearanceDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayAppearanceDef.itemheight := LINEHEIGHT2;
  OptionsDisplayAppearanceDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAdvancedMenu
  pmi := @OptionsDisplayAdvancedMenu[0];

  pmi.status := 1;
  pmi.name := '!Fullscreen';
  pmi.cmd := 'fullscreen';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @fullscreen;
  pmi.alphaKey := 'f';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Mirror Mode';
  pmi.cmd := '';
  pmi.routine := @M_SwitchMirrorMode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'm';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Transparent sprites';
  pmi.cmd := 'usetransparentsprites';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @usetransparentsprites;
  pmi.alphaKey := 't';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Uncapped framerate';
  pmi.cmd := 'interpolate';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @interpolate;
  pmi.alphaKey := 'u';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Z-Axis Shift';
  pmi.cmd := 'zaxisshift';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @zaxisshift;
  pmi.alphaKey := 'z';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Chase camera';
  pmi.cmd := 'chasecamera';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @chasecamera;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Fix memory stall hack';
  pmi.cmd := 'fixstallhack';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @fixstallhack;
  pmi.alphaKey := 'f';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Widescreen support';
  pmi.cmd := 'widescreensupport';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @widescreensupport;
  pmi.alphaKey := 'w';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Player Sprites Stretch';
  pmi.cmd := 'excludewidescreenplayersprites';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @excludewidescreenplayersprites;
  pmi.alphaKey := 'p';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayAdvancedDef
  OptionsDisplayAdvancedDef.title := 'Advanced';
  OptionsDisplayAdvancedDef.numitems := Ord(optdispadvanced_end); // # of menu items
  OptionsDisplayAdvancedDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplayAdvancedDef.leftMenu := @OptionsDisplayAppearanceDef; // left menu
  OptionsDisplayAdvancedDef.rightMenu := @OptionsDisplayColorsDef; // right menu
  OptionsDisplayAdvancedDef.menuitems := Pmenuitem_tArray(@OptionsDisplayAdvancedMenu);  // menu items
  OptionsDisplayAdvancedDef.drawproc := @M_DrawOptionsDisplayAdvanced;  // draw routine
  OptionsDisplayAdvancedDef.x := 32;
  OptionsDisplayAdvancedDef.y := 68; // x,y of menu
  OptionsDisplayAdvancedDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayAdvancedDef.itemheight := LINEHEIGHT2;
  OptionsDisplayAdvancedDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayColorsMenu
  pmi := @OptionsDisplayColorsMenu[0];

  pmi.status := 1;
  pmi.name := '!Grayscale Mode';
  pmi.cmd := '';
  pmi.routine := @M_SwitchGrayscaleMode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'g';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Palette reduction';
  pmi.cmd := '';
  pmi.routine := @M_SwitchColorsSubsampling;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'q';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplayColorsDef
  OptionsDisplayColorsDef.title := 'Colors';
  OptionsDisplayColorsDef.numitems := Ord(optdispcolors_end); // # of menu items
  OptionsDisplayColorsDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplayColorsDef.leftMenu := @OptionsDisplayAdvancedDef; // left menu
  OptionsDisplayColorsDef.rightMenu := @OptionsLightmapDef; // right menu
  OptionsDisplayColorsDef.menuitems := Pmenuitem_tArray(@OptionsDisplayColorsMenu);  // menu items
  OptionsDisplayColorsDef.drawproc := @M_DrawOptionsDisplayColors;  // draw routine
  OptionsDisplayColorsDef.x := 32;
  OptionsDisplayColorsDef.y := 68; // x,y of menu
  OptionsDisplayColorsDef.lastOn := 0; // last item user was on in menu
  OptionsDisplayColorsDef.itemheight := LINEHEIGHT2;
  OptionsDisplayColorsDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsLightmapMenu
  pmi := @OptionsLightmapMenu[0];

  pmi.status := 1;
  pmi.name := '!Light effects';
  pmi.cmd := 'uselightmap';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @uselightmap;
  pmi.alphaKey := 'l';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Accuracy';
  pmi.cmd := '';
  pmi.routine := @M_ChangeLightmapAccuracy;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'a';

  inc(pmi);
  pmi.status := 2;
  pmi.name := '!Color intensity';
  pmi.cmd := '';
  pmi.routine := @M_ChangeLightmapColorIntensity;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 2;
  pmi.name := '!Distance from source';
  pmi.cmd := '';
  pmi.routine := @M_ChangeLightmapLightWidthFactor;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'd';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 2;
  pmi.name := '!Reset to default';
  pmi.cmd := '';
  pmi.routine := @M_LightmapDefaults;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'r';

////////////////////////////////////////////////////////////////////////////////
//OptionsLightmapDef
  OptionsLightmapDef.title := 'Lightmap';
  OptionsLightmapDef.numitems := Ord(ol_lightmap_end); // # of menu items
  OptionsLightmapDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsLightmapDef.leftMenu := @OptionsDisplayColorsDef; // left menu
  OptionsLightmapDef.rightMenu := @OptionsDisplay32bitDef; // right menu
  OptionsLightmapDef.menuitems := Pmenuitem_tArray(@OptionsLightmapMenu);  // menu items
  OptionsLightmapDef.drawproc := @M_DrawOptionsLightmap;  // draw routine
  OptionsLightmapDef.x := 32;
  OptionsLightmapDef.y := 68; // x,y of menu
  OptionsLightmapDef.lastOn := 0; // last item user was on in menu
  OptionsLightmapDef.itemheight := LINEHEIGHT2;
  OptionsLightmapDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplay32bitMenu
  pmi := @OptionsDisplay32bitMenu[0];

  pmi.status := 1;
  pmi.name := '!Use 32 bit colormaps';
  pmi.cmd := 'forcecolormaps';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @forcecolormaps;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!32 bit palette effect simulation';
  pmi.cmd := '32bittexturepaletteeffects';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @dc_32bittexturepaletteeffects;
  pmi.alphaKey := 'p';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Use classic fuzz effect in 32 bit';
  pmi.cmd := 'use32bitfuzzeffect';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @use32bitfuzzeffect;
  pmi.alphaKey := 'f';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Use external textures';
  pmi.cmd := 'useexternaltextures';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @useexternaltextures;
  pmi.alphaKey := 'x';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Search texture paths in PK3';
  pmi.cmd := 'preferetexturesnamesingamedirectory';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @preferetexturesnamesingamedirectory;
  pmi.alphaKey := 'p';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_ChangeFlatFiltering;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'f';

////////////////////////////////////////////////////////////////////////////////
//OptionsDisplay32bitDef
  OptionsDisplay32bitDef.title := '32 bit rendering';
  OptionsDisplay32bitDef.numitems := Ord(optdisp32bit_end); // # of menu items
  OptionsDisplay32bitDef.prevMenu := @OptionsDisplayDef; // previous menu
  OptionsDisplay32bitDef.leftMenu := @OptionsLightmapDef; // left menu
  OptionsDisplay32bitDef.rightMenu := @OptionsDisplayDetailDef; // right menu
  OptionsDisplay32bitDef.menuitems := Pmenuitem_tArray(@OptionsDisplay32bitMenu);  // menu items
  OptionsDisplay32bitDef.drawproc := @M_DrawOptionsDisplay32bit;  // draw routine
  OptionsDisplay32bitDef.x := 32;
  OptionsDisplay32bitDef.y := 68; // x,y of menu
  OptionsDisplay32bitDef.lastOn := 0; // last item user was on in menu
  OptionsDisplay32bitDef.itemheight := LINEHEIGHT2;
  OptionsDisplay32bitDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//ReadMenu1
  pmi := @ReadMenu1[0];
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_ReadThis2;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

////////////////////////////////////////////////////////////////////////////////
//ReadDef1
  ReadDef1.numitems := Ord(read1_end); // # of menu items
  ReadDef1.prevMenu := @MainDef; // previous menu
  ReadDef1.menuitems := Pmenuitem_tArray(@ReadMenu1);  // menu items
  ReadDef1.drawproc := @M_DrawReadThis1;  // draw routine
  ReadDef1.x := 330;
  ReadDef1.y := 165; // x,y of menu
  ReadDef1.lastOn := 0; // last item user was on in menu
  ReadDef1.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//ReadMenu2
  pmi := @ReadMenu2[0];
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_FinishReadThis;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

////////////////////////////////////////////////////////////////////////////////
//ReadDef2
  ReadDef2.numitems := Ord(read2_end); // # of menu items
  ReadDef2.prevMenu := @ReadDef1; // previous menu
  ReadDef2.menuitems := Pmenuitem_tArray(@ReadMenu2);  // menu items
  ReadDef2.drawproc := @M_DrawReadThis2;  // draw routine
  ReadDef2.x := 330;
  ReadDef2.y := 165; // x,y of menu
  ReadDef2.lastOn := 0; // last item user was on in menu
  ReadDef2.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//SoundMenu
  pmi := @SoundMenu[0];
  pmi.status := 1;
  pmi.name := '!Volume Control';
  pmi.cmd := '';
  pmi.routine := @M_SoundVolume;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'v';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Use external WAV files';
  pmi.cmd := 'useexternalwav';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @useexternalwav;
  pmi.alphaKey := 'w';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Search WAV paths in PK3';
  pmi.cmd := 'preferewavnamesingamedirectory';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @preferewavnamesingamedirectory;
  pmi.alphaKey := 's';

////////////////////////////////////////////////////////////////////////////////
//SoundDef
  SoundDef.title := 'Sound';
  SoundDef.numitems := Ord(sound_end); // # of menu items
  SoundDef.prevMenu := @OptionsDef; // previous menu
  SoundDef.leftMenu := @SystemDef; // left menu
  SoundDef.rightMenu := @CompatibilityDef; // left menu
  SoundDef.menuitems := Pmenuitem_tArray(@SoundMenu);  // menu items
  SoundDef.drawproc := @M_DrawSound;  // draw routine
  SoundDef.x := 32;
  SoundDef.y := 68; // x,y of menu
  SoundDef.lastOn := 0; // last item user was on in menu
  SoundDef.itemheight := LINEHEIGHT2;
  SoundDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//SoundVolMenu
  pmi := @SoundVolMenu[0];
  pmi.status := 2;
  pmi.name := 'M_SFXVOL';
  pmi.cmd := '';
  pmi.routine := @M_SfxVol;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 2;
  pmi.name := 'M_MUSVOL';
  pmi.cmd := '';
  pmi.routine := @M_MusicVol;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'm';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

////////////////////////////////////////////////////////////////////////////////
//SoundVolDef
  SoundVolDef.numitems := Ord(soundvol_end); // # of menu items
  SoundVolDef.prevMenu := @SoundDef; // previous menu
  SoundVolDef.menuitems := Pmenuitem_tArray(@SoundVolMenu);  // menu items
  SoundVolDef.drawproc := @M_DrawSoundVol;  // draw routine
  SoundVolDef.x := 80;
  SoundVolDef.y := 64; // x,y of menu
  SoundVolDef.lastOn := 0; // last item user was on in menu
  SoundVolDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//CompatibilityMenu
  pmi := @CompatibilityMenu[0];
  pmi.status := 1;
  pmi.name := '!Allow player jumps';
  pmi.cmd := 'allowplayerjumps';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @allowplayerjumps;
  pmi.alphaKey := 'j';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Keep cheats when reborn';
  pmi.cmd := 'keepcheatsinplayerreborn';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @keepcheatsinplayerreborn;
  pmi.alphaKey := 'c';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Boss death ends Doom1 level';
  pmi.cmd := 'majorbossdeathendsdoom1level';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @majorbossdeathendsdoom1level;
  pmi.alphaKey := 'd';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Spawn random monsters';
  pmi.cmd := 'spawnrandommonsters';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @spawnrandommonsters;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Splashes on special terrains';
  pmi.cmd := 'allowterrainsplashes';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @allowterrainsplashes;
  pmi.alphaKey := 't';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Monsters fight after player death';
  pmi.cmd := 'continueafterplayerdeath';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @continueafterplayerdeath;
  pmi.alphaKey := 'f';


////////////////////////////////////////////////////////////////////////////////
//CompatibilityDef
  CompatibilityDef.title := 'Compatibility';
  CompatibilityDef.numitems := Ord(cmp_end); // # of menu items
  CompatibilityDef.prevMenu := @OptionsDef; // previous menu
  CompatibilityDef.leftMenu := @SoundDef; // left menu
  CompatibilityDef.rightMenu := @ControlsDef; // right menu
  CompatibilityDef.menuitems := Pmenuitem_tArray(@CompatibilityMenu);  // menu items
  CompatibilityDef.drawproc := @M_DrawCompatibility;  // draw routine
  CompatibilityDef.x := 32;
  CompatibilityDef.y := 68; // x,y of menu
  CompatibilityDef.lastOn := 0; // last item user was on in menu
  CompatibilityDef.itemheight := LINEHEIGHT2;
  CompatibilityDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//ControlsMenu
  pmi := @ControlsMenu[0];
  pmi.status := 1;
  pmi.name := '!Use mouse';
  pmi.cmd := 'use_mouse';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @usemouse;
  pmi.alphaKey := 'm';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Invert mouse up/down look';
  pmi.cmd := 'invertmouselook';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @invertmouselook;
  pmi.alphaKey := 'i';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Invert mouse turn left/right';
  pmi.cmd := 'invertmouseturn';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @invertmouseturn;
  pmi.alphaKey := 'i';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Mouse sensitivity...';
  pmi.cmd := '';
  pmi.routine := @M_OptionsSensitivity;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Use joystic';
  pmi.cmd := 'use_joystick';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @usejoystick;
  pmi.alphaKey := 'j';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Always run';
  pmi.cmd := 'autorunmode';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @autorunmode;
  pmi.alphaKey := 'a';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := @M_SwitchKeyboardMode;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'k';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Customize...';
  pmi.cmd := '';
  pmi.routine := @M_KeyBindings;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'b';

////////////////////////////////////////////////////////////////////////////////
//ControlsDef
  ControlsDef.title := 'Controls';
  ControlsDef.numitems := Ord(ctrl_end); // # of menu items
  ControlsDef.prevMenu := @OptionsDef; // previous menu
  ControlsDef.leftMenu := @CompatibilityDef; // left menu
  ControlsDef.rightMenu := @SystemDef; // left menu
  ControlsDef.menuitems := Pmenuitem_tArray(@ControlsMenu);  // menu items
  ControlsDef.drawproc := @M_DrawControls;  // draw routine
  ControlsDef.x := 32;
  ControlsDef.y := 68; // x,y of menu
  ControlsDef.lastOn := 0; // last item user was on in menu
  ControlsDef.itemheight := LINEHEIGHT2;
  ControlsDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//SensitivityMenu
  pmi := @SensitivityMenu[0];
  pmi.status := 2;
  pmi.name := '!Global sensitivity';
  pmi.cmd := '';
  pmi.routine := @M_ChangeSensitivity;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'x';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 2;
  pmi.name := '!X Axis sensitivity';
  pmi.cmd := '';
  pmi.routine := @M_ChangeSensitivityX;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'x';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := 2;
  pmi.name := '!Y Axis sensitivity';
  pmi.cmd := '';
  pmi.routine := @M_ChangeSensitivityY;
  pmi.pBoolVal := nil;
  pmi.alphaKey := 'y';

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

  inc(pmi);
  pmi.status := -1;
  pmi.name := '';
  pmi.cmd := '';
  pmi.routine := nil;
  pmi.pBoolVal := nil;
  pmi.alphaKey := #0;

////////////////////////////////////////////////////////////////////////////////
//SensitivityDef
  SensitivityDef.title := 'Mouse sensitivity';
  SensitivityDef.numitems := Ord(sens_end); // # of menu items
  SensitivityDef.prevMenu := @ControlsDef; // previous menu
  SensitivityDef.menuitems := Pmenuitem_tArray(@SensitivityMenu);  // menu items
  SensitivityDef.drawproc := @M_DrawSensitivity;  // draw routine
  SensitivityDef.x := 32;
  SensitivityDef.y := 68; // x,y of menu
  SensitivityDef.lastOn := 0; // last item user was on in menu
  SensitivityDef.itemheight := LINEHEIGHT2;
  SensitivityDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//SystemMenu
  pmi := @SystemMenu[0];
  pmi.status := 1;
  pmi.name := '!Safe mode';
  pmi.cmd := 'safemode';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @safemode;
  pmi.alphaKey := 's';

  inc(pmi);
  pmi.status := 1;
  pmi.name := '!Use mmx/AMD 3D-Now';
  pmi.cmd := 'mmx';
  pmi.routine := @M_BoolCmd;
  pmi.pBoolVal := @usemmx;
  pmi.alphaKey := 'm';

////////////////////////////////////////////////////////////////////////////////
//SystemDef
  SystemDef.title := 'System';
  SystemDef.numitems := Ord(sys_end); // # of menu items
  SystemDef.prevMenu := @OptionsDef; // previous menu
  SystemDef.leftMenu := @ControlsDef; // left menu
  SystemDef.rightMenu := @SoundDef; // right menu
  SystemDef.menuitems := Pmenuitem_tArray(@SystemMenu);  // menu items
  SystemDef.drawproc := @M_DrawSystem;  // draw routine
  SystemDef.x := 32;
  SystemDef.y := 68; // x,y of menu
  SystemDef.lastOn := 0; // last item user was on in menu
  SystemDef.itemheight := LINEHEIGHT2;
  SystemDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//KeyBindingsMenu
  pmi := @KeyBindingsMenu[0];
  for i := 0 to Ord(kb_end) - 1 do
  begin
    pmi.status := 1;
    pmi.name := '!' + KeyBindingsInfo[i].text;
    pmi.cmd := '';
    pmi.routine := @M_KeyBindingSelect;
    pmi.pBoolVal := nil;
    pmi.alphaKey := Chr(Ord('1') + i);
    inc(pmi);
  end;

////////////////////////////////////////////////////////////////////////////////
//KeyBindingsDef
  KeyBindingsDef.numitems := Ord(kb_end); // # of menu items
  KeyBindingsDef.prevMenu := @ControlsDef; // previous menu
  KeyBindingsDef.menuitems := Pmenuitem_tArray(@KeyBindingsMenu);  // menu items
  KeyBindingsDef.drawproc := @M_DrawBindings;  // draw routine
  KeyBindingsDef.x := 32;
  KeyBindingsDef.y := 34; // x,y of menu
  KeyBindingsDef.lastOn := 0; // last item user was on in menu
  KeyBindingsDef.itemheight := LINEHEIGHT2;
  KeyBindingsDef.texturebk := true;

////////////////////////////////////////////////////////////////////////////////
//LoadMenu
  pmi := @LoadMenu[0];
  for i := 0 to Ord(load_end) - 1 do
  begin
    pmi.status := 1;
    pmi.name := '';
    pmi.cmd := '';
    pmi.routine := @M_LoadSelect;
    pmi.pBoolVal := nil;
    pmi.alphaKey := Chr(Ord('1') + i);
    inc(pmi);
  end;

////////////////////////////////////////////////////////////////////////////////
//LoadDef
  LoadDef.numitems := Ord(load_end); // # of menu items
  LoadDef.prevMenu := @MainDef; // previous menu
  LoadDef.menuitems := Pmenuitem_tArray(@LoadMenu);  // menu items
  LoadDef.drawproc := @M_DrawLoad;  // draw routine
  LoadDef.x := 80;
  LoadDef.y := 34; // x,y of menu
  LoadDef.lastOn := 0; // last item user was on in menu
  LoadDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
//SaveMenu
  pmi := @SaveMenu[0];
  for i := 0 to Ord(load_end) - 1 do
  begin
    pmi.status := 1;
    pmi.name := '';
    pmi.cmd := '';
    pmi.routine := @M_SaveSelect;
    pmi.alphaKey := Chr(Ord('1') + i);
    pmi.pBoolVal := nil;
    inc(pmi);
  end;

////////////////////////////////////////////////////////////////////////////////
//SaveDef
  SaveDef.numitems := Ord(load_end); // # of menu items
  SaveDef.prevMenu := @MainDef; // previous menu
  SaveDef.menuitems := Pmenuitem_tArray(@SaveMenu);  // menu items
  SaveDef.drawproc := M_DrawSave;  // draw routine
  SaveDef.x := 80;
  SaveDef.y := 34; // x,y of menu
  SaveDef.lastOn := 0; // last item user was on in menu
  SaveDef.itemheight := LINEHEIGHT;

////////////////////////////////////////////////////////////////////////////////
  joywait := 0;
  mousewait := 0;
  mmousex := 0;
  mmousey := 0;
  mlastx := 0;
  mlasty := 0;

end;

end.
