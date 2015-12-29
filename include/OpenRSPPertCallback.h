/*
  OpenRSP: open-ended library for response theory
  Copyright 2015 Radovan Bast,
                 Daniel H. Friese,
                 Bin Gao,
                 Dan J. Jonsson,
                 Magnus Ringholm,
                 Kenneth Ruud,
                 Andreas Thorvaldsen

  OpenRSP is free software: you can redistribute it and/or modify
  it under the terms of the GNU Lesser General Public License as
  published by the Free Software Foundation, either version 3 of
  the License, or (at your option) any later version.

  OpenRSP is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with OpenRSP. If not, see <http://www.gnu.org/licenses/>.


  This is the header file of perturbations' callback function.

  2014-07-31, Bin Gao:
  * first version
*/

#if !defined(OPENRSP_PERT_CALLBACK_H)
#define OPENRSP_PERT_CALLBACK_H

#include "OpenRSP.h"

#if defined(OPENRSP_C_USER_CONTEXT)
#define PERT_CONTEXT "NRNZGEO"
#endif

extern void get_pert_concatenation(const QInt,
                                   const QcPertInt,
                                   const QInt,
                                   const QInt,
                                   const QInt*,
#if defined(OPENRSP_C_USER_CONTEXT)
                                   void*,
#endif
                                   QInt*);

#endif