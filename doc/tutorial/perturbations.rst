.. _chapter_perturbations:

Perturbations
=============

**NOTE**: although the perturbation free scheme is not fully implemented, users
still need to set up information of perturbations using the API
:c:func:`OpenRSPSetPerturbations` except that the callback function
:c:func:`get_pert_concatenation` can be a faked one.

To make OpenRSP a perturbation free library:

#. The components of each perturbation, i.e., the number of components and
   their arrangement in memory are totally decided by the host program, and
   OpenRSP gets such information from callback functions.
#. OpenRSP will follow the order of perturbation labels sent by the APIs
   :c:func:`OpenRSPGetRSPFun` or :c:func:`OpenRSPGetResidue` during runtime, to
   generate necessary perturbation tuples during calculations, and such a order
   is named as **canonical order**.
#. OpenRSP will also use canonical order when preparing a collection of
   perturbation tuples, that for instance could be sent to the callback
   functions of exchange-correlation functionals.

All these can be done by first calling the API
:c:func:`OpenRSPSetPerturbations` to set up all the different perturbation
labels involved in calculations.

For instance, if we have electric, magnetic and geometric perturbations in our
calculations. We will use three different integers to distinguish them, let us
say ``EL``, ``MAG`` and ``GEO``.

Our integral codes can only handle ``EL`` to the first order, ``MAG`` to the
second order and ``GEO`` to the third order.

Our codes use the redundant format of derivatives, i.e. there will be 9
components for the second order magnetic derivatives
(:math:`xx,xy,xz,yx,yy,yz,zx,zy,zz`) instead of 6 (:math:`xx,xy,xz,yy,yz,zz`),
and :math:`9N_{\text{atoms}}^{2}` and :math:`27N_{\text{atoms}}^{3}` second and
third order geometric derivatives, where :math:`N_{\text{atoms}}` is the number
of atoms.

Therefore, we can set:

#. ``num_pert=3``,
#. ``pert_labels[3]={EL,MAG,GEO}``,
#. ``pert_max_orders[3]={1,2,3}``,
#. ``pert_num_comps[6]={3, 3,9, 3*N,9*N*N,27*N*N*N}``,

where ``N`` is the number of atoms and should be defined. So ``pert_num_comps``
actually tells OpenRSP the number of components of different perturbation
labels from the first order up to their maximum order.

The last argument is a callback function :c:func:`get_pert_concatenation` for
getting the ranks of components of sub-perturbation tuples (with same
perturbation label) for given components of the corresponding concatenated
perturbation tuple. Here the name of the function can be anything else.

This callback function has been discussed in :ref:`chapter_callback_functions`.
Here we will show an example.

For instance, during the calculations, OpenRSP may need to calculate quantities
of the second order magnetic derivatives from those of the first order
(redundant format):

* :math:`x+x\rightarrow xx`, :math:`x+y\rightarrow xy`, :math:`x+z\rightarrow xz`,
* :math:`y+x\rightarrow yx`, :math:`y+y\rightarrow yy`, :math:`y+z\rightarrow yz`,
* :math:`z+x\rightarrow zx`, :math:`z+y\rightarrow zy`, :math:`z+z\rightarrow zz`,

or, if we rank these derivatives (zero-based numbering):

* :math:`0+0\rightarrow 0`, :math:`0+1\rightarrow 1`, :math:`0+2\rightarrow 2`,
* :math:`1+0\rightarrow 3`, :math:`1+1\rightarrow 4`, :math:`1+2\rightarrow 5`,
* :math:`2+0\rightarrow 6`, :math:`2+1\rightarrow 7`, :math:`2+2\rightarrow 8`.

That means, if OpenRSP sends:

#. ``pert_label=MAG``,
#. ``first_cat_comp=0``,
#. ``num_cat_comps=9``,
#. ``num_sub_tuples=2``,
#. ``len_sub_tuples[2]={1,1}``,

the callback function :c:func:`get_pert_concatenation` should return:
``rank_sub_comps[2*9]={0,0, 0,1, 0,2, 1,0, 1,1, 1,2, 2,0, 2,1, 2,2}``, or other
correct way to construct the second derivatives.

The use of the callback function :c:func:`get_pert_concatenation` makes it
possible for the hose program to choose different formats of derivatives.

For instance, if the host program use non-redundant format of derivatives, i.e.
there will be 6 components for the second order magnetic derivatives
(:math:`xx,xy,xz,yy,yz,zz`), and
:math:`\frac{3N_{\text{atoms}}(3N_{\text{atoms}}+1)}{2}` and
:math:`\frac{3N_{\text{atoms}}(3N_{\text{atoms}}+1)(3N_{\text{atoms}}+2)}{6}`
second and third order geometric derivatives.

For the non-redundant second order magnetic derivatives, OpenRSP could send:

#. ``pert_label=MAG``,
#. ``first_cat_comp=0``,
#. ``num_cat_comps=6``,
#. ``num_sub_tuples=2``,
#. ``len_sub_tuples[2]={1,1}``,

and get:

``rank_sub_comps[2*6]={0,0, 0,1, 0,2, 1,1, 1,2, 2,2}``.

Therefore, the use of the callback function :c:func:`get_pert_concatenation`
makes host programs fully control the components of different derivatives, and
makes OpenRSP perturbation free.

Last, the second last argument ``usr_ctx`` is the user defined context for the
callback function :c:func:`get_pert_concatenation`. This argument can be used
to pass additional but necessary information to the callback function, and
OpenRSP will not touch it.
