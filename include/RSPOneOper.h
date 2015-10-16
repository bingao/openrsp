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


  <header name='RSPOneOper.h' author='Bin Gao' date='2014-07-30'>
    The header file of one-electron operators used inside OpenRSP
  </header>
*/

#if !defined(RSP_ONEOPER_H)
#define RSP_ONEOPER_H

#include "qcmatrix.h"
#include "RSPPerturbation.h"

typedef QVoid (*GetOneOperMat)(const QInt,
                               const QcPertInt*,
                               const QInt*,
#if defined(OPENRSP_C_USER_CONTEXT)
                               QVoid*,
#endif
                               const QInt,
                               QcMat*[]);
typedef QVoid (*GetOneOperExp)(const QInt,
                               const QcPertInt*,
                               const QInt*,
                               const QInt,
                               QcMat*[],
#if defined(OPENRSP_C_USER_CONTEXT)
                               QVoid*,
#endif
                               const QInt,
                               QReal*);

typedef struct RSPOneOper RSPOneOper;
struct RSPOneOper {
    QInt num_pert_lab;               /* number of different perturbation labels
                                        that can act as perturbations on the
                                        one-electron operator */
    QInt oper_num_pert;              /* number of perturbations on the
                                        one-electron operator, only used for
                                        callback functions */
    QInt *pert_max_orders;           /* allowed maximal order of a perturbation
                                        described by exactly one of these
                                        different labels */
    QInt *oper_pert_orders;          /* orders of perturbations on the
                                        one-electron operator, only used for
                                        callback functions */
    QcPertInt *pert_labels;          /* all the different perturbation labels */
    QcPertInt *oper_pert_labels;     /* labels of perturbations on the
                                        one-electron operator, only used for
                                        callback functions */
#if defined(OPENRSP_C_USER_CONTEXT)
    QVoid *user_ctx;                 /* user-defined callback-function context */
#endif
    GetOneOperMat get_one_oper_mat;  /* user-specified function for calculating
                                        integral matrices */
    GetOneOperExp get_one_oper_exp;  /* user-specified function for calculating
                                        expectation values */
    RSPOneOper *next_oper;           /* pointer to the next one-electron operator */
};

extern QErrorCode RSPOneOperCreate(RSPOneOper**,
                                   const QInt,
                                   const QcPertInt*,
                                   const QInt*,
#if defined(OPENRSP_C_USER_CONTEXT)
                                   QVoid*,
#endif
                                   const GetOneOperMat,
                                   const GetOneOperExp);
extern QErrorCode RSPOneOperAdd(RSPOneOper*,
                                const QInt,
                                const QcPertInt*,
                                const QInt*,
#if defined(OPENRSP_C_USER_CONTEXT)
                                QVoid*,
#endif
                                const GetOneOperMat,
                                const GetOneOperExp);
extern QErrorCode RSPOneOperAssemble(RSPOneOper*,const RSPPert*);
extern QErrorCode RSPOneOperWrite(RSPOneOper*,FILE*);
extern QErrorCode RSPOneOperGetMat(RSPOneOper*,
                                   const QInt,
                                   const QcPertInt*,
                                   const QInt,
                                   QcMat*[]);
extern QErrorCode RSPOneOperGetExp(RSPOneOper*,
                                   const QInt,
                                   const QcPertInt*,
                                   const QInt,
                                   QcMat*[],
                                   const QInt,
                                   QReal*);
extern QErrorCode RSPOneOperDestroy(RSPOneOper**);

#endif
