! Copyright 2012 Magnus Ringholm
!
! This file is made available under the terms of the
! GNU Lesser General Public License version 3.

! Contains routines for the calculation of perturbed
! overlap, density and Fock matrices used throughout the
! rsp_general calculation.

module rsp_perturbed_sdf

!  use matrix_defop, matrix => openrsp_matrix
!  use matrix_lowlevel, only: mat_init, mat_zero_like
  use rsp_contribs
  use rsp_field_tuple
  use rsp_indices_and_addressing
  use rsp_perturbed_matrices
  use rsp_sdf_caching
  use rsp_lof_caching
!  use interface_2el
  
  use qcmatrix_f

  implicit none


  public rsp_fds_2014
  public get_fds_2014
  public rsp_fock_lowerorder_2014
  public get_fock_lowerorder_2014

  private

  real(8) :: time_start
  real(8) :: time_end

  contains

  

  recursive subroutine rsp_fds_2014(pert, kn, F, D, S, get_rsp_sol, get_ovl_mat, &
                               get_1el_mat, get_2el_mat, get_xc_mat, id_outp)

    implicit none

    
    type(p_tuple) :: pert
    type(p_tuple), dimension(pert%n_perturbations) :: psub
    integer, dimension(2) :: kn
    integer :: i, j, k, id_outp
    type(SDF_2014) :: F, D, S
    external :: get_rsp_sol, get_ovl_mat, get_1el_mat,  get_2el_mat, get_xc_mat



    ! Unless at final recursion level, recurse further
    ! Make all size (n - 1) subsets of the perturbations and recurse
    ! Then (at final recursion level) get perturbed F, D, S 
    if (pert%n_perturbations > 1) then

       call make_p_tuple_subset(pert, psub)

       do i = 1, size(psub)

          if (sdf_already_2014(D, psub(i)) .eqv. .FALSE.) then

             call rsp_fds_2014(psub(i), kn, F, D, S, get_rsp_sol, get_ovl_mat, &
                          get_1el_mat, get_2el_mat, get_xc_mat, id_outp)

          end if

       end do       

    end if

    if (sdf_already_2014(D, pert) .eqv. .FALSE.) then
         
       if (kn_skip(pert%n_perturbations, pert%pid, kn) .eqv. .FALSE.) then

          write(id_outp,*) 'Calling ovlint/fock/density with labels ', pert%plab, &
                     ' and perturbation id ', pert%pid, ' with frequencies (real part)', &
                     real(pert%freq)
          write(id_outp,*) ' '
                 
          k = 1

          do j = 1, pert%n_perturbations

             pert%pid(j) = k
             k = k + 1

          end do

          call get_fds_2014(p_tuple_standardorder(pert), F, D, S, get_rsp_sol, &
                       get_ovl_mat, get_1el_mat, get_2el_mat, get_xc_mat, id_outp)

       else

!           write(*,*) 'Would have called ovlint/fock/density with labels ', &
!                      pert%plab, ' and perturbation id ', pert%pid, &
!                      ' but it was k-n forbidden'
!           write(*,*) ' '

       end if

    else

!        write(*,*) 'FDS for labels ', pert%plab, &
!                   'and perturbation id ', pert%pid, ' was found in cache'
!        write(*,*) ' '

    end if

  end subroutine
  
  



    subroutine get_fds_2014(pert, F, D, S, get_rsp_sol, get_ovl_mat, &
                       get_1el_mat, get_2el_mat, get_xc_mat, id_outp)

!    use interface_rsp_solver, only: rsp_solver_exec
    implicit none

    
    integer :: sstr_incr, i, j, superstructure_size, nblks, perturbed_matrix_size, id_outp
    integer :: ierr, npert_ext
    integer, allocatable, dimension(:) :: ind, blk_sizes, pert_ext, pert_ord_ext
    integer, allocatable, dimension(:,:) :: blk_info, indices
    integer, dimension(0) :: noc
    character(4), dimension(0) :: nof
    type(p_tuple) :: pert
    type(p_tuple), allocatable, dimension(:,:) :: derivative_structure
    type(SDF_2014) :: F, D, S
    external :: get_rsp_sol, get_ovl_mat, get_1el_mat, get_2el_mat, get_xc_mat
    type(QcMat) :: X(1), RHS(1), A, B, C, zeromat, T, U
    type(QcMat), allocatable, dimension(:) :: Fp, Dp, Sp, Dh
    type(f_l_cache_2014), pointer :: fock_lowerorder_cache


    ! ASSUME CLOSED SHELL
    
    call QcMatInit(A)
    call QcMatInit(B)
    call QcMatInit(C)
    call QcMatInit(T)
    call QcMatInit(U)
    
    
    call sdf_getdata_s_2014(D, get_emptypert(), (/1/), A)
    call sdf_getdata_s_2014(S, get_emptypert(), (/1/), B)
    call sdf_getdata_s_2014(F, get_emptypert(), (/1/), C)
    
    

    nblks = get_num_blks(pert)

    allocate(blk_info(nblks, 3))
    allocate(blk_sizes(pert%n_perturbations))

    blk_info = get_blk_info(nblks, pert)
    perturbed_matrix_size = get_triangulated_size(nblks, blk_info)
    blk_sizes = get_triangular_sizes(nblks, blk_info(:,2), blk_info(:,3))

    allocate(Fp(perturbed_matrix_size))
    allocate(Dp(perturbed_matrix_size))
    allocate(Sp(perturbed_matrix_size))
    allocate(Dh(perturbed_matrix_size))

    ! Process perturbation tuple for external call
    
    call p_tuple_external(pert, npert_ext, pert_ext, pert_ord_ext)
    
    
    ! Get the appropriate Fock/density/overlap matrices

    ! 1. Call ovlint and store perturbed overlap matrix


    do i = 1, perturbed_matrix_size

       ! ASSUME CLOSED SHELL
!        call mat_init(Sp(i), zeromat%nrow, zeromat%ncol, is_zero=.true.)
    call QcMatInit(Sp(i))

    end do
! write(*,*) 'Sp a', Sp(1)%elms

    call get_ovl_mat(0, noc, noc, 0, noc, noc, npert_ext, pert_ext, pert_ord_ext, &
                     perturbed_matrix_size, Sp)

!     call rsp_ovlint(zeromat%nrow, pert%n_perturbations, pert%plab, &
!                        (/ (1, j = 1, pert%n_perturbations) /), pert%pdim, &
!                        nblks, blk_info, blk_sizes, &
!                        perturbed_matrix_size, Sp)

! write(*,*) 'Sp b', Sp(1)%elms

    call sdf_add_2014(S, pert, perturbed_matrix_size, Sp)

    deallocate(blk_sizes)

    ! INITIALIZE AND STORE D INSTANCE WITH ZEROES
    ! THE ZEROES WILL ENSURE THAT TERMS INVOLVING THE HIGHEST ORDER DENSITY MATRICES
    ! WILL BE ZERO IN THE CONSTRUCTION OF Dp

    do i = 1, perturbed_matrix_size

       ! ASSUME CLOSED SHELL
!        call mat_init(Dp(i), zeromat%nrow, zeromat%ncol, is_zero=.true.)
    call QcMatInit(Dp(i), Sp(1))

!        call mat_init(Dh(i), zeromat%nrow, zeromat%ncol, is_zero=.true.)
    call QcMatInit(Dh(i), Sp(1))

!        call mat_init(Fp(i), zeromat%nrow, zeromat%ncol, is_zero=.true.)
    call QcMatInit(Fp(i), Sp(1))

    end do

    call sdf_add_2014(D, pert, perturbed_matrix_size, Dp)

    ! 2. Construct Dp and the initial part of Fp
    ! a) For the initial part of Fp: Make the initial recursive (lower order) 
    ! oneint, twoint, and xcint calls as needed

! write(*,*) 'Fp a', Fp(1)%elms

    call f_l_cache_allocate_2014(fock_lowerorder_cache)
    call rsp_fock_lowerorder_2014(pert, pert%n_perturbations, 1, (/get_emptypert()/), &
                         get_1el_mat, get_ovl_mat, get_2el_mat, get_xc_mat, 0, D, &
                         perturbed_matrix_size, Fp, fock_lowerorder_cache)

! write(*,*) 'Fp b', Fp(1)%elms

    deallocate(fock_lowerorder_cache)

    call sdf_add_2014(F, pert, perturbed_matrix_size, Fp)

    ! b) For Dp: Create differentiation superstructure: First dryrun for size, and
    ! then the actual superstructure call

    superstructure_size = derivative_superstructure_getsize(pert, &
                          (/pert%n_perturbations, pert%n_perturbations/), .FALSE., &
                          (/get_emptypert(), get_emptypert(), get_emptypert()/))

    sstr_incr = 0

    allocate(derivative_structure(superstructure_size, 3))
    allocate(indices(perturbed_matrix_size, pert%n_perturbations))
    allocate(ind(pert%n_perturbations))

    call derivative_superstructure(pert, (/pert%n_perturbations, &
         pert%n_perturbations/), .FALSE., &
         (/get_emptypert(), get_emptypert(), get_emptypert()/), &
         superstructure_size, sstr_incr, derivative_structure)
    call make_triangulated_indices(nblks, blk_info, perturbed_matrix_size, indices)

    do i = 1, size(indices, 1)

       ind = indices(i, :)

! write(*,*) 'Dp 0', Dp(1)%elms

       call rsp_get_matrix_z_2014(superstructure_size, derivative_structure, &
               (/pert%n_perturbations,pert%n_perturbations/), pert%n_perturbations, &
               (/ (j, j = 1, pert%n_perturbations) /), pert%n_perturbations, &
               ind, F, D, S, Dp(i))

! write(*,*) 'Dp 1', Dp(1)%elms


!      Dp(i) = Dp(i) - A * B * Dp(i) - Dp(i) * B * A
       call QcMatkABC(-1.0d0, Dp(i), B, A, T)
       call QcMatkABC(-1.0d0, A, B, Dp(i), U)
       call QcMatRAXPY(1.0d0, T, U)
       call QcMatRAXPY(1.0d0, U, Dp(i))


       
       
! write(*,*) 'Dp 2', Dp(1)%elms


       call sdf_add_2014(D, pert, perturbed_matrix_size, Dp)

       ! 3. Complete the particular contribution to Fp
! write(*,*) 'Fp b2', Fp(1)%elms
       call cpu_time(time_start)
       call get_2el_mat(0, noc, noc, 1, (/Dp(i)/), 1, Fp(i:i))
!        call rsp_twoint(zeromat%nrow, 0, nof, noc, pert%pdim, Dp(i), &
!                           1, Fp(i:i))
       call cpu_time(time_end)
!        print *, 'seconds spent in 2-el particular contribution', time_end - time_start
! write(*,*) 'Fp b3', Fp(1)%elms

       call cpu_time(time_start)
       ! MaR: Reintroduce once callback functionality is complete
!        call get_xc_mat(0, pert%pdim, noc, nof, 2, (/A, Dp(i)/), Fp(i:i))
!        call rsp_xcint_adapt(zeromat%nrow, 0, nof, noc, pert%pdim, &
!             (/ A, Dp(i) /) , 1, Fp(i:i))
       call cpu_time(time_end)
!       print *, 'seconds spent in XC particular contribution', time_end - time_start

       ! MaR: Considered to be part of the 2el call
!        call cpu_time(time_start)
!        call rsp_pe(zeromat%nrow, 0, nof, noc, pert%pdim, Dp(i) , 1, Fp(i))
!        call cpu_time(time_end)
! !       print *, 'seconds spent in PE particular contribution', time_end - time_start

! write(*,*) 'Fp b4', Fp(1)%elms

       call sdf_add_2014(F, pert, perturbed_matrix_size, Fp)
! write(*,*) 'Fp c', Fp(1)%elms


       ! 4. Make right-hand side using Dp

    call QcMatInit(RHS(1))
    call QcMatInit(X(1))

       call rsp_get_matrix_y_2014(superstructure_size, derivative_structure, &
                pert%n_perturbations, (/ (j, j = 1, pert%n_perturbations) /), &
                pert%n_perturbations, ind, F, D, S, RHS(1))


       ! Note (MaR): Passing only real part of freq. Is this OK?
       ! MaR: May need to vectorize RHS and X
       
       call get_rsp_sol(1, (/sum(real(pert%freq(:)))/), 1, RHS, X)
       
!        call get_rsp_sol(RHS(1), 1, (/sum(real(pert%freq(:)))/), X)
!        call rsp_solver_exec(RHS(1), (/sum(real(pert%freq(:)))/), X)

       call QcMatDst(RHS(1))

       ! 5. Get Dh using the rsp equation solution X
       
!        Dh(i) = A*B*X(1) - X(1)*B*A
       call QcMatkABC(-1.0d0, X(1), B, A, T)
       call QcMatkABC(1.0d0, A, B, X(1), U)
       call QcMatRAXPY(1.0d0, T, U)
       call QcMatAEqB(Dh(i), U)

       ! 6. Make homogeneous contribution to Fock matrix

       call cpu_time(time_start)
       call get_2el_mat(0, noc, noc, 1, (/Dh(i)/), 1, Fp(i:i))

       call cpu_time(time_end)
!        print *, 'seconds spent in 2-el homogeneous contribution', time_end - time_start
! write(*,*) 'Fp b3', Fp(1)%elms

       call cpu_time(time_start)
       ! MaR: Reintroduce once callback functionality is complete
!        call get_xc_mat(0, pert%pdim, noc, nof, 2, (/A, Dp(i)/), Fp(i:i))
!        call rsp_xcint_adapt(zeromat%nrow, 0, nof, noc, pert%pdim, &
!             (/ A, Dh(i) /) , 1, Fp(i:i))
       call cpu_time(time_end)
!       print *, 'seconds spent in XC homogeneous contribution', time_end - time_start
       
       
       
!        call cpu_time(time_start)
!        call rsp_twoint(zeromat%nrow, 0, nof, noc, pert%pdim, Dh(i), &
!                           1, Fp(i:i))
!        call cpu_time(time_end)
!        print *, 'seconds spent in 2-el homogeneous contribution', time_end - time_start

!        call cpu_time(time_start)
!        call rsp_xcint_adapt(zeromat%nrow, 0, nof, noc, pert%pdim, &
!             (/ A, Dh(i) /) , 1, Fp(i:i))
!        call cpu_time(time_end)
!        print *, 'seconds spent in XC homogeneous contribution', time_end - time_start

!        call cpu_time(time_start)
!        call rsp_pe(zeromat%nrow, 0, nof, noc, pert%pdim, Dh(i), 1, Fp(i))
!        call cpu_time(time_end)
!       print *, 'seconds spent in PE homogeneous contribution', time_end - time_start

       ! 7. Complete perturbed D with homogeneous part

!        Dp(i) = Dp(i) + Dh(i)
       call QcMatRAXPY(1.0d0, Dh(i), Dp(i))


if (perturbed_matrix_size < 10) then

write(*,*) 'Finished component', i, ':', (float(i)/float(perturbed_matrix_size))*100, '% done'
  

else

if (mod(i, perturbed_matrix_size/10) == 1) then

write(*,*) 'Finished component', i, ':', (float(i)/float(perturbed_matrix_size))*100, '% done'

end if

end if


!        write(*,*) ' '
!        write(*,*) 'Finally, Dp is:'
!        write(*,*) Dp(i)%elms
!        write(*,*) ' '
!        write(*,*) 'Finally, Fp is:'
!        write(*,*) Fp(i)%elms
!        write(*,*) ' '
!        write(*,*) 'Finally, Sp is:'
!        write(*,*) Sp(i)%elms_alpha
!        write(*,*) ' '

    end do

    ! Add the final values to cache

    call sdf_add_2014(F, pert, perturbed_matrix_size, Fp)
    call sdf_add_2014(D, pert, perturbed_matrix_size, Dp)

    do i = 1, size(indices, 1)

       call QcMatDst(Dh(i))
       call QcMatDst(Dp(i))
       call QcMatDst(Fp(i))
       call QcMatDst(Sp(i))
       
    end do

    
    call QcMatDst(A)
    call QcMatDst(B)
    call QcMatDst(C)
    call QcMatDst(T)
    call QcMatDst(U)

    deallocate(derivative_structure)
    deallocate(ind)
    deallocate(pert_ext)
    deallocate(pert_ord_ext)
    deallocate(Fp)
    deallocate(Dp)
    deallocate(Sp)
    deallocate(Dh)
    deallocate(blk_info)

  end subroutine
  
  
  
  

  
  
    recursive subroutine rsp_fock_lowerorder_2014(pert, total_num_perturbations, &
                       num_p_tuples, p_tuples, get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
                       density_order, D, property_size, Fp, fock_lowerorder_cache)

    implicit none

    logical :: density_order_skip
    type(p_tuple) :: pert
    integer :: num_p_tuples, density_order, i, j, total_num_perturbations, property_size
    type(p_tuple), dimension(num_p_tuples) :: p_tuples, t_new
    type(SDF_2014) :: D
    external :: get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat
    type(QcMat), dimension(property_size) :: Fp
    type(f_l_cache_2014) :: fock_lowerorder_cache

    if (pert%n_perturbations >= 1) then

       ! The differentiation can do three things:
       ! 1. Differentiate the expression 'directly'

       if (p_tuples(1)%n_perturbations == 0) then

          call rsp_fock_lowerorder_2014(p_tuple_remove_first(pert), & 
               total_num_perturbations, num_p_tuples, &
               (/p_tuple_getone(pert,1), p_tuples(2:size(p_tuples))/), &
               get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
               density_order, D, property_size, Fp, fock_lowerorder_cache)

       else

          call rsp_fock_lowerorder_2014(p_tuple_remove_first(pert), &
               total_num_perturbations, num_p_tuples, &
               (/p_tuple_extend(p_tuples(1), p_tuple_getone(pert,1)), &
               p_tuples(2:size(p_tuples))/), &
               get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
               density_order, D, property_size, Fp, fock_lowerorder_cache)

       end if
    
       ! 2. Differentiate all of the contraction densities in turn

       do i = 2, num_p_tuples

          t_new = p_tuples

          if (p_tuples(i)%n_perturbations == 0) then

             t_new(i) = p_tuple_getone(pert, 1)

          else

             t_new(i) = p_tuple_extend(t_new(i), p_tuple_getone(pert, 1))

          end if

          call rsp_fock_lowerorder_2014(p_tuple_remove_first(pert), &
               total_num_perturbations, num_p_tuples, &
               t_new, get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
               density_order + 1, D, property_size, Fp, fock_lowerorder_cache)

       end do

       ! 3. Chain rule differentiate w.r.t. the density (giving 
       ! a(nother) pert D contraction)

       call rsp_fock_lowerorder_2014(p_tuple_remove_first(pert), &
            total_num_perturbations, num_p_tuples + 1, &
            (/p_tuples(:), p_tuple_getone(pert, 1)/), &
            get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
            density_order + 1, D, property_size, Fp, fock_lowerorder_cache)

    else

!        p_tuples = p_tuples_standardorder(num_p_tuples, p_tuples)

       density_order_skip = .FALSE.

       do i = 2, num_p_tuples

          if (p_tuples(i)%n_perturbations >= total_num_perturbations) then

             density_order_skip = .TRUE.

          end if

       end do
      
       if (density_order_skip .EQV. .FALSE.) then

          if (f_l_cache_already_2014(fock_lowerorder_cache, &
          num_p_tuples, p_tuples_standardorder(num_p_tuples, p_tuples)) .EQV. .FALSE.) then

       write(*,*) 'Calculating perturbed Fock matrix lower order contribution'

       do i = 1, num_p_tuples
 
          if (i == 1) then

             write(*,*) 'F', p_tuples(i)%pid

          else

             write(*,*) 'D', p_tuples(i)%pid

          end if

       end do

             call get_fock_lowerorder_2014(num_p_tuples, total_num_perturbations, &
                                      p_tuples_standardorder(num_p_tuples, p_tuples), &
                                      density_order, get_1el_mat, get_t_mat, get_2el_mat, get_xc_mat, &
                                      D, property_size, Fp, fock_lowerorder_cache)

             write(*,*) 'Calculated perturbed Fock matrix lower order contribution'
             write(*,*) ' '

          else

             call f_l_cache_getdata_2014(fock_lowerorder_cache, num_p_tuples, &
                                    p_tuples_standardorder(num_p_tuples, p_tuples), &
                                    property_size, Fp)

!              write(*,*) ' '

          end if

       else

!           write(*,*) 'Skipping contribution: At least one contraction D perturbed' 
!           write(*,*) 'at order for which perturbed D is to be found '
!           write(*,*) ' '

       end if

    end if

  end subroutine




  subroutine get_fock_lowerorder_2014(num_p_tuples, total_num_perturbations, p_tuples, &
                                 density_order, get_1el_mat, get_ovl_mat, get_2el_mat, get_xc_mat, &
                                 D, property_size, Fp, fock_lowerorder_cache)

    implicit none
    
    type(p_tuple) :: merged_p_tuple, t_matrix_bra, t_matrix_ket, t_matrix_newpid
    type(p_tuple), dimension(num_p_tuples) :: p_tuples
    type(SDF_2014) :: D
    type(QcMat), allocatable, dimension(:) :: dens_tuple
    integer :: i, j, k, m, num_p_tuples, total_num_perturbations, merged_nblks, &
               density_order, property_size, fp_offset, lo_offset, inner_indices_size, &
               outer_indices_size, merged_triang_size, offset, npert_ext
    integer, dimension(0) :: noc
    integer, dimension(total_num_perturbations) :: ncarray, ncouter, ncinner, pidouter, &
                                                pids_current_contribution, translated_index
    integer, allocatable, dimension(:) :: o_whichpert, o_whichpertbig, o_wh_forave
    integer, allocatable, dimension(:) :: ncoutersmall, pidoutersmall, ncinnersmall
    integer, allocatable, dimension(:) :: nfields, nblks_tuple, blks_tuple_triang_size
    integer, allocatable, dimension(:) :: blk_sizes_merged, pert_ext, pert_ord_ext
    integer, allocatable, dimension(:,:) :: outer_indices, inner_indices
    integer, allocatable, dimension(:,:) :: triang_indices_fp, blk_sizes
    integer, allocatable, dimension(:,:,:) :: merged_blk_info, blks_tuple_info
    external :: get_1el_mat, get_ovl_mat, get_2el_mat, get_xc_mat
    type(QcMat) :: zeromat, D_unp
    type(QcMat), allocatable, dimension(:) :: tmp, lower_order_contribution
    type(QcMat), dimension(property_size) :: Fp
    type(f_l_cache_2014) :: fock_lowerorder_cache

!    ncarray = get_ncarray(total_num_perturbations, num_p_tuples, p_tuples)
!    ncouter = nc_only(total_num_perturbations, total_num_perturbations - & 
!                      p_tuples(1)%n_perturbations, num_p_tuples - 1, &
!                      p_tuples(2:num_p_tuples), ncarray)
!    ncinner = nc_only(total_num_perturbations, p_tuples(1)%n_perturbations, 1, &
!                      p_tuples(1), ncarray)

    allocate(ncoutersmall(total_num_perturbations - p_tuples(1)%n_perturbations))
    allocate(ncinnersmall(p_tuples(1)%n_perturbations))
    allocate(pidoutersmall(total_num_perturbations - p_tuples(1)%n_perturbations))

!    ncoutersmall = nc_onlysmall(total_num_perturbations, total_num_perturbations - &
!                                p_tuples(1)%n_perturbations, num_p_tuples - 1, &
!                                p_tuples(2:num_p_tuples), ncarray)
!    ncinnersmall = nc_onlysmall(total_num_perturbations, p_tuples(1)%n_perturbations, &
!                   1, p_tuples(1), ncarray)
!    pidoutersmall = get_pidoutersmall(total_num_perturbations - &
!                    p_tuples(1)%n_perturbations, num_p_tuples - 1, &
 !                   p_tuples(2:num_p_tuples))

    ! MaR: Second way of blks_tuple_info can in the general case be larger than
    ! needed, but is allocated this way to get a prismic data structure
    allocate(blks_tuple_info(num_p_tuples, total_num_perturbations, 3))
    allocate(blks_tuple_triang_size(num_p_tuples))
    allocate(blk_sizes(num_p_tuples, total_num_perturbations))
    allocate(blk_sizes_merged(total_num_perturbations))
    allocate(o_whichpert(total_num_perturbations))
    allocate(o_wh_forave(total_num_perturbations))
    !FIXME Gao: we do not need dens_tuple(1)?
    allocate(dens_tuple(2:num_p_tuples))
    allocate(nfields(num_p_tuples))
    allocate(nblks_tuple(num_p_tuples))

    
    call p_tuple_external(p_tuples(1), npert_ext, pert_ext, pert_ord_ext)
    
    
    call p_tuple_p1_cloneto_p2(p_tuples(1), t_matrix_newpid)
    t_matrix_newpid%pid = (/(i, i = 1, t_matrix_newpid%n_perturbations)/)


    do i = 1, num_p_tuples

       nfields(i) = p_tuples(i)%n_perturbations
       nblks_tuple(i) = get_num_blks(p_tuples(i))

    end do

    do i = 1, num_p_tuples

       call get_blk_info_s(nblks_tuple(i), p_tuples(i), blks_tuple_info(i, 1:nblks_tuple(i), :))

! write(*,*) blks_tuple_info(i, :, :)
! write(*,*) 'sanitized'
! write(*,*) blks_tuple_info(i, 1:nblks_tuple(i), :)

       blks_tuple_triang_size(i) = get_triangulated_size(nblks_tuple(i), &
                                   blks_tuple_info(i, 1:nblks_tuple(i), :))


! write(*,*)  blks_tuple_triang_size(i) 

       blk_sizes(i, 1:nblks_tuple(i)) = get_triangular_sizes(nblks_tuple(i), &
       blks_tuple_info(i,1:nblks_tuple(i),2), blks_tuple_info(i,1:nblks_tuple(i),3))

    end do

    outer_indices_size = product(blks_tuple_triang_size(2:num_p_tuples))

    if (p_tuples(1)%n_perturbations == 0) then

       inner_indices_size = 1

    else

       inner_indices_size = blks_tuple_triang_size(1)

    end if

    allocate(tmp(inner_indices_size))
    allocate(lower_order_contribution(inner_indices_size * outer_indices_size))

    o_whichpert = make_outerwhichpert(total_num_perturbations, num_p_tuples, p_tuples)
!    call sortdimbypid(total_num_perturbations, total_num_perturbations - &
!                      p_tuples(1)%n_perturbations, pidoutersmall, &
!                      ncarray, ncoutersmall, o_whichpert)

    call sdf_getdata_s_2014(D, get_emptypert(), (/1/), D_unp)

    !FIXME Gao: we should allocate and initialize lower_order_contribution and
    !           dens_tuple in the if statement where they are used, also their
    !           deallocation should be moved
    do j = 1, size(lower_order_contribution)
       call QcMatInit(lower_order_contribution(j))
    end do

    do j = 1, size(tmp)
       call QcMatInit(tmp(j))
    end do

    do i = 2, num_p_tuples
       call QcMatInit(dens_tuple(j))
    end do

    if (total_num_perturbations > p_tuples(1)%n_perturbations) then

       k = 1

       do i = 2, num_p_tuples
          do j = 1, p_tuples(i)%n_perturbations

             o_wh_forave(p_tuples(i)%pid(j)) = k
             k = k + 1

          end do
       end do

       allocate(outer_indices(outer_indices_size,total_num_perturbations - &
                p_tuples(1)%n_perturbations))
       allocate(inner_indices(inner_indices_size,p_tuples(1)%n_perturbations))

       call make_triangulated_tuples_indices(num_p_tuples - 1, total_num_perturbations, & 
            nblks_tuple(2:num_p_tuples), blks_tuple_info(2:num_p_tuples, &
            :, :), blks_tuple_triang_size(2:num_p_tuples), outer_indices)

       if (p_tuples(1)%n_perturbations > 0) then

          call make_triangulated_indices(nblks_tuple(1), blks_tuple_info(1, &
               1:nblks_tuple(1), :), blks_tuple_triang_size(1), inner_indices)

       end if

       do i = 1, size(outer_indices, 1)

          do j = 2, num_p_tuples

             call sdf_getdata_s_2014(D, p_tuples(j), (/ &
                             (outer_indices(i,o_wh_forave(p_tuples(j)%pid(k))), &
                             k = 1, p_tuples(j)%n_perturbations) /), dens_tuple(j))

          end do

          if (num_p_tuples <= 2) then

             call cpu_time(time_start)
             
             call get_2el_mat(npert_ext, pert_ext, pert_ord_ext, 1, (/dens_tuple(2)/), size(tmp), tmp)
             
!              call rsp_twoint(zeromat%nrow, p_tuples(1)%n_perturbations, p_tuples(1)%plab, &
!                              (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                              p_tuples(1)%pdim, dens_tuple(2), size(tmp), tmp)
             call cpu_time(time_end)
!              print *, 'seconds spent in 2-el contribution', time_end - time_start
          end if

          ! MaR: Reintroduce after minimal working version is complete
          call cpu_time(time_start)
          
!           call get_xc_mat(p_tuples(1)%n_perturbations, p_tuples(1)%pdim, &
!                           (/ (1, j = 1, p_tuples(1)%n_perturbations) /), p_tuples(1)%plab, &
!                           num_p_tuples, (/ D_unp, (dens_tuple(k), k = 2, num_p_tuples) /), tmp)
          
!           call rsp_xcint_adapt(zeromat%nrow, p_tuples(1)%n_perturbations, &
!                p_tuples(1)%plab, (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                p_tuples(1)%pdim, (/ D_unp, &
!                (dens_tuple(k), k = 2, num_p_tuples) /), property_size, tmp)
          call cpu_time(time_end)
!           print *, 'seconds spent in XC contribution', time_end - time_start

          ! MaR: Remove and consider as part of 2el contribution
!           if (num_p_tuples <= 2) then
!              call cpu_time(time_start)
!              call rsp_pe(zeromat%nrow, p_tuples(1)%n_perturbations, p_tuples(1)%plab, &
!                              (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                              p_tuples(1)%pdim, dens_tuple(2), size(tmp), tmp)
!              call cpu_time(time_end)
! !             print *, 'seconds spent in PE contribution', time_end - time_start
!           end if

          if (p_tuples(1)%n_perturbations > 0) then

             do j = 1, size(inner_indices,1)

                offset = get_triang_blks_tuple_offset(num_p_tuples, total_num_perturbations, &
                nblks_tuple, (/ (p_tuples(k)%n_perturbations, k = 1, num_p_tuples) /), &
                blks_tuple_info, blk_sizes, blks_tuple_triang_size, &
                (/inner_indices(j, :), outer_indices(i, :) /)) 

                call QcMatAEqB(lower_order_contribution(offset),tmp(j))

             end do

          else

             ! MaR: There might be problems with this call (since the first p_tuple is empty)

             offset = get_triang_blks_tuple_offset(num_p_tuples - 1, total_num_perturbations, &
             nblks_tuple(2:num_p_tuples), &
             (/ (p_tuples(k)%n_perturbations, k = 2, num_p_tuples) /), &
             blks_tuple_info(2:num_p_tuples, :, :), blk_sizes(2:num_p_tuples,:), & 
             blks_tuple_triang_size(2:num_p_tuples), (/outer_indices(i, :) /)) 

             call QcMatAEqB(lower_order_contribution(offset),tmp(1))

          end if

       end do

       if (p_tuples(1)%n_perturbations > 0) then

          call p_tuple_p1_cloneto_p2(p_tuples(1), merged_p_tuple)

          do i = 2, num_p_tuples

             ! MaR: This can be problematic - consider rewriting merge_p_tuple as subroutine
             merged_p_tuple = merge_p_tuple(merged_p_tuple, p_tuples(i))

          end do

       else

          call p_tuple_p1_cloneto_p2(p_tuples(2), merged_p_tuple)

          do i = 3, num_p_tuples

             ! MaR: This can be problematic - consider rewriting merge_p_tuple as subroutine
             merged_p_tuple = merge_p_tuple(merged_p_tuple, p_tuples(i))

          end do

       end if

       merged_p_tuple = p_tuple_standardorder(merged_p_tuple)

       k = 1
       do i = 1, num_p_tuples
          do j = 1, p_tuples(i)%n_perturbations
             pids_current_contribution(k) = p_tuples(i)%pid(j)
             k = k + 1
          end do
       end do

! write(*,*) 'merged plab', merged_p_tuple%plab

       merged_nblks = get_num_blks(merged_p_tuple)

! write(*,*) 'merged plab 2', merged_p_tuple%plab

       allocate(merged_blk_info(1, merged_nblks, 3))

! write(*,*) 'allocate OK', merged_p_tuple%plab

       call get_blk_info_s(merged_nblks, merged_p_tuple, merged_blk_info(1, :, :))

! write(*,*) 'merged plab 3', merged_p_tuple%plab
! 
! do i = 1, merged_nblks
! 
! write(*,*) 'merged block info', merged_blk_info(1,i,:)
! 
! end do

       blk_sizes_merged(1:merged_nblks) = get_triangular_sizes(merged_nblks, &
       merged_blk_info(1,1:merged_nblks,2), merged_blk_info(1,1:merged_nblks,3))
       merged_triang_size = get_triangulated_size(merged_nblks, merged_blk_info)

       allocate(triang_indices_fp(merged_triang_size, sum(merged_blk_info(1, :,2))))

       call make_triangulated_indices(merged_nblks, merged_blk_info, & 
            merged_triang_size, triang_indices_fp)

! do i = 1, size(triang_indices_fp,1)
! 
! write(*,*) 'triang indices', triang_indices_fp(i,:)
! 
! end do
! 
! write(*,*) 'size Fp', size(Fp)
! write(*,*) 'size loc', size(lower_order_contribution)


       do i = 1, size(triang_indices_fp, 1)

          fp_offset = get_triang_blks_tuple_offset(1, merged_nblks, (/merged_nblks/), &
                      (/sum(nfields)/), &
                      (/merged_blk_info/), blk_sizes_merged, (/merged_triang_size/), &
                      (/triang_indices_fp(i, :) /))

          do j = 1, total_num_perturbations
    
             translated_index(j) = triang_indices_fp(i,pids_current_contribution(j))
    
          end do

          if (p_tuples(1)%n_perturbations > 0) then

             lo_offset = get_triang_blks_tuple_offset(num_p_tuples, &
                         total_num_perturbations, nblks_tuple, &
                         nfields, blks_tuple_info, blk_sizes, blks_tuple_triang_size, &
                         (/translated_index(:)/))

          else

             lo_offset = get_triang_blks_tuple_offset(num_p_tuples - 1, &
                         total_num_perturbations, nblks_tuple(2:num_p_tuples), &
                         nfields(2:num_p_tuples), blks_tuple_info(2:num_p_tuples, :, :), &
                         blk_sizes(2:num_p_tuples,:), &
                         blks_tuple_triang_size(2:num_p_tuples), & 
                         (/translated_index(:)/))

          end if

          call QcMatRAXPY(1.0d0, lower_order_contribution(lo_offset), Fp(fp_offset))

       end do

       call f_l_cache_add_element_2014(fock_lowerorder_cache, num_p_tuples, p_tuples, &
            inner_indices_size * outer_indices_size, lower_order_contribution)

       deallocate(merged_blk_info)
       deallocate(triang_indices_fp)
       deallocate(outer_indices)
       deallocate(inner_indices)

    else

       if (num_p_tuples <= 1) then

          call get_1el_mat(npert_ext, pert_ext, pert_ord_ext, size(tmp), tmp)
       
!           call rsp_oneint(zeromat%nrow, p_tuples(1)%n_perturbations, p_tuples(1)%plab, &
!                           (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                           p_tuples(1)%pdim, nblks_tuple(1), blks_tuple_info(1, &
!                    1:nblks_tuple(1), :), blk_sizes(1, 1:nblks_tuple(1)), property_size, Fp)

! NOTE: Find out if necessary ovlint/oneint in "outer indices case" above
! NOTE (Oct 12): Probably not unless some hidden density matrix dependence

          t_matrix_bra = get_emptypert()
          t_matrix_ket = get_emptypert()

          call rsp_ovlint_t_matrix_2014(t_matrix_newpid%n_perturbations, t_matrix_newpid, &
                                   t_matrix_bra, t_matrix_ket, get_ovl_mat, property_size, Fp)

       end if

       if (num_p_tuples <= 2) then

          call cpu_time(time_start)
          
          call get_2el_mat(npert_ext, pert_ext, pert_ord_ext, 1, (/D_unp/), size(tmp), tmp)
          
                      
!           call rsp_twoint(zeromat%nrow, p_tuples(1)%n_perturbations, p_tuples(1)%plab, &
!                (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                p_tuples(1)%pdim, D_unp, &
!                property_size, Fp)
          call cpu_time(time_end)
!           print *, 'seconds spent in 2-el contribution', time_end - time_start

       end if

       ! MaR: Reintroduce when minimal working version is complete
!        call cpu_time(time_start)
!        call rsp_xcint_adapt(zeromat%nrow, p_tuples(1)%n_perturbations, p_tuples(1)%plab, &
!                       (/ (1, j = 1, p_tuples(1)%n_perturbations) /), &
!                       p_tuples(1)%pdim, &
!                       (/ D_unp /), &
!                       property_size, Fp)
!        call cpu_time(time_end)
! !        print *, 'seconds spent in XC contribution', time_end - time_start

       ! MaR: Remove and consider as part of 2el contribution
!        if (num_p_tuples <= 2) then
!           call cpu_time(time_start)
!           call rsp_pe(zeromat%nrow,                                 &
!                       p_tuples(1)%n_perturbations,                  &
!                       p_tuples(1)%plab,                             &
!                       (/ (1, j = 1, p_tuples(1)%n_perturbations) /),&
!                       p_tuples(1)%pdim,                             &
!                       D_unp,                                        &
!                       property_size,                                &
!                       Fp)
!           call cpu_time(time_end)
! !          print *, 'seconds spent in PE contribution', time_end - time_start
!        end if

       ! MaR: THERE IS NO NEED TO CACHE THE "ALL INNER" CONTRIBUTION
       ! It should be possible to just add it to Fp like already done above
       ! even with the extra complexity from the triangularization 

    end if

    call QcMatDst(D_unp)

    do i = 2, num_p_tuples
   
       call QcMatDst(dens_tuple(i))
   
    end do

    do i = 1, size(tmp)

       call QcMatDst(tmp(i))

    end do

    do i = 1, size(lower_order_contribution)

       call QcMatDst(lower_order_contribution(i))

    end do

    deallocate(dens_tuple)


    deallocate(pert_ext)
    deallocate(pert_ord_ext)
    
    deallocate(nfields)
    deallocate(nblks_tuple)
    deallocate(blks_tuple_info)
    deallocate(blks_tuple_triang_size)
    deallocate(blk_sizes)
    deallocate(blk_sizes_merged)
    deallocate(ncoutersmall)
    deallocate(ncinnersmall)
    deallocate(pidoutersmall)
    deallocate(o_whichpert)
    deallocate(o_wh_forave)
    deallocate(tmp)
    deallocate(lower_order_contribution)

    ! MaR: Why is the next line commented? Find out
!     deallocate(dens_tuple)

  end subroutine
  
  
  end module