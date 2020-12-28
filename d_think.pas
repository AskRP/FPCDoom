//------------------------------------------------------------------------------
//
//  FPCDoom - Port of Doom to Free Pascal Compiler
//  Copyright (C) 1993-1996 by id Software, Inc.
//  Copyright (C) 2004-2007 by Jim Valavanis
//  Copyright (C) 2017-2020 by Jim Valavanis
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
//  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
//  02111-1307, USA.
//
//------------------------------------------------------------------------------
//  E-Mail: jimmyvalavanis@yahoo.gr
//  Site  : https://sourceforge.net/projects/fpcdoom/
//------------------------------------------------------------------------------

{$I FPCDoom.inc}

unit d_think;

interface

type
  actionf_v = procedure;
  actionf_p1 = procedure(p1: pointer);
  actionf_p2 = procedure(p1, p2: pointer);

  actionf_t = record
    case integer of
      0: (acp1: actionf_p1);
      1: (acv: actionf_v);
      2: (acp2: actionf_p2);
    end;
  Pactionf_t = ^actionf_t;
  actionf_tArray = array[0..$FFFF] of actionf_t;
  Pactionf_tArray = ^actionf_tArray;

  think_t = actionf_t;
  Pthink_t = ^think_t;

  Pthinker_t = ^thinker_t;
  thinker_t = record
    prev: Pthinker_t;
    next: Pthinker_t;
    _function: think_t;
  end;

implementation

end.
