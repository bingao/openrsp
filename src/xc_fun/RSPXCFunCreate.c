/* OpenRSP: open-ended library for response theory
   Copyright 2014

   OpenRSP is free software: you can redistribute it and/or modify
   it under the terms of the GNU Lesser General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   OpenRSP is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
   GNU Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public License
   along with OpenRSP. If not, see <http://www.gnu.org/licenses/>.

   This file implements the function RSPTwoOperCreate().

   2014-08-06, Bin Gao:
   * first version
*/

#include "hamiltonian/rsp_two_oper.h"

/*% \brief creates the linked list of two-electron operators,
        should be called at first
    \author Bin Gao
    \date 2014-08-06
    \param[RSPTwoOper:struct]{inout} two_oper the linked list of two-electron operators
    \param[QInt:int]{in} num_pert number of perturbations that the two-electron
        operator depends on
    \param[QInt:int]{in} pert_labels labels of the perturbations
    \param[QInt:int]{in} pert_max_orders maximum allowed orders of the perturbations
    \param[QVoid:void]{in} user_ctx user-defined callback function context
    \param[GetTwoOperMat:void]{in} get_two_oper_mat user specified function for
        getting integral matrices
    \param[GetTwoOperExp:void]{in} get_two_oper_exp user specified function for
        getting expectation values
    \return[QErrorCode:int] error information
*/
QErrorCode RSPTwoOperCreate(RSPTwoOper **two_oper,
                            const QInt num_pert,
                            const QInt *pert_labels,
                            const QInt *pert_max_orders,
                            QVoid *user_ctx,
                            const GetTwoOperMat get_two_oper_mat,
                            const GetTwoOperExp get_two_oper_exp)
{
    RSPTwoOper *new_oper;  /* new operator */
    QInt ipert,jpert;      /* incremental recorder over perturbations */
    new_oper = (RSPTwoOper *)malloc(sizeof(RSPTwoOper));
    if (new_oper==NULL) {
        QErrorExit(FILE_AND_LINE, "failed to allocate memory for new_oper");
    }
    if (num_pert>0) {
        new_oper->num_pert = num_pert;
    }
    else {
        printf("RSPTwoOperCreate>> number of perturbations %d\n", num_pert);
        QErrorExit(FILE_AND_LINE, "invalid number of perturbations");
    }
    new_oper->pert_labels = (QInt *)malloc(num_pert*sizeof(QInt));
    if (new_oper->pert_labels==NULL) {
        printf("RSPTwoOperCreate>> number of perturbations %d\n", num_pert);
        QErrorExit(FILE_AND_LINE, "failed to allocate memory for pert_labels");
    }
    new_oper->pert_max_orders = (QInt *)malloc(num_pert*sizeof(QInt));
    if (new_oper->pert_max_orders==NULL) {
        printf("RSPTwoOperCreate>> number of perturbations %d\n", num_pert);
        QErrorExit(FILE_AND_LINE, "failed to allocate memory for pert_max_orders");
    }
    for (ipert=0; ipert<num_pert; ipert++) {
        /* each element of \var{pert_labels} should be unique */
        for (jpert=0; jpert<ipert; jpert++) {
            if (pert_labels[jpert]==pert_labels[ipert]) {
                printf("RSPTwoOperCreate>> perturbation %d is %d\n",
                       jpert,
                       pert_labels[jpert]);
                printf("RSPTwoOperCreate>> perturbation %d is %d\n",
                       ipert,
                       pert_labels[ipert]);
                QErrorExit(FILE_AND_LINE, "same perturbation not allowed");
            }
        }
        new_oper->pert_labels[ipert] = pert_labels[ipert];
        if (pert_max_orders[ipert]<1) {
            printf("RSPTwoOperCreate>> order of %d-th perturbation (%d) is %d\n",
                   ipert,
                   pert_labels[ipert],
                   pert_max_orders[ipert]);
            QErrorExit(FILE_AND_LINE, "only positive order allowed");
        }
        new_oper->pert_max_orders[ipert] = pert_max_orders[ipert];
    }
    new_oper->user_ctx = user_ctx;
    new_oper->get_two_oper_mat = get_two_oper_mat;
    new_oper->get_two_oper_exp = get_two_oper_exp;
    new_oper->next_oper = NULL;
    *two_oper = new_oper;
    return QSUCCESS;
}