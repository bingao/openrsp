! Copyright 2012      Magnus Ringholm
!
! This file is made available under the terms of the
! GNU Lesser General Public License version 3.

! Contains routines/functions and definitions related to the SDF datatype
! in which (perturbed) overlap, density and Fock matrices are stored.

module rsp_sdf_caching

  use rsp_field_tuple
  use rsp_indices_and_addressing
  use matrix_defop

  implicit none

  public sdf_init
  public sdf_getdata_s
  public sdf_getdata
  public sdf_next_element
  public sdf_add
  public sdf_already


  ! Define perturbed S, D, or F linked list datatype

  type SDF

     type(SDF), pointer :: next
     logical :: last
     ! Should all of the data attributes be pointers too?
     type(p_tuple) :: perturb
     type(matrix), allocatable, dimension(:) :: data ! (Perturbed) matrix data

  ! Note(MaR): Like for property_cache, a good extension here would be 
  ! to let the data attribute point to a function/routine that manages retrieval 
  ! (and storage) of values. This will allow better management of very large pieces 
  ! of data, for instance by letting the function manage whether some (large) piece 
  ! of data is stored on disk (and retrieved from there) or if, for smaller pieces 
  ! of data or, in case of parallel implementations, the data is stored in memory.

  end type

  contains

  ! Begin SDF linked list manipulation/data retrieval routines

  subroutine sdf_init(new_element, pert, perturbed_matrix_size, data)

    implicit none

    type(SDF) :: new_element
    type(p_tuple) :: pert
    type(matrix), dimension(product(pert%pdim)) :: data
    integer :: i, perturbed_matrix_size

    new_element%last = .TRUE.

    call p_tuple_p1_cloneto_p2(pert, new_element%perturb)
    allocate(new_element%data(perturbed_matrix_size))

! write(*,*) 'mat size', perturbed_matrix_size
! write(*,*) 'npert', pert%n_perturbations
! write(*,*) 'pid', pert%pid
! write(*,*) 'pdim', pert%pdim
! write(*,*) 'plab', pert%plab
! write(*,*) 'freq', pert%freq

    do i = 1, perturbed_matrix_size
    
! write(*,*) 'i is', i
!        call mat_ensure_alloc(data(i))
! write(*,*) 'first alloc'
!        new_element%data(i)%complex = .FALSE.
!        new_element%data(i)%open_shell = .FALSE.
       new_element%data(i) = mat_alloc_like(data(i))
! write(*,*) 'alloc'
       new_element%data(i) = mat_zero_like(data(i))
! write(*,*) 'zero'
       call mat_ensure_alloc(new_element%data(i))
! write(*,*) 'ensure'
       new_element%data(i) = data(i)
! write(*,*) 'assign'
! write(*,*) 'element finished'

    end do
 
  end subroutine

  ! Get SDF element
  ! Assumes that pert_tuple and the p_tuple in current_element is in standard order

  subroutine sdf_getdata_s(current_element, pert_tuple, ind_unsorted, M)

    implicit none

    logical :: found
    type(SDF), target :: current_element
    type(SDF), pointer :: next_element
    type(p_tuple) :: pert_tuple
    type(matrix) :: M
    integer, dimension(pert_tuple%n_perturbations) :: ind, ind_unsorted
    integer :: i, offset, passedlast, nblks, sorted_triangulated_indices
    integer, allocatable, dimension(:,:) :: blk_info
    integer, allocatable, dimension(:) :: blk_sizes

    next_element => current_element

ind = ind_unsorted
    if (pert_tuple%n_perturbations > 0) then

! write(*,*) 'getting offset for ind', ind
! write(*,*) 'plabs are', pert_tuple%plab

       nblks = get_num_blks(pert_tuple)
       allocate(blk_sizes(nblks))
       allocate(blk_info(nblks, 3))
       blk_info = get_blk_info(nblks, pert_tuple)
       blk_sizes = get_triangular_sizes(nblks, blk_info(:,2), blk_info(:,3))

! write(*,*) 'blk info in sdf_getdata_s', blk_info(:,2)
       call sort_triangulated_indices(pert_tuple%n_perturbations, nblks, &
                                         blk_info, ind)

! write(*,*) 'sorted triang indices', ind


       offset = get_triang_blks_offset(nblks, pert_tuple%n_perturbations, &
                                       blk_info, blk_sizes, ind)

! write(*,*) 'got offset', offset

       deallocate(blk_sizes)
       deallocate(blk_info)

! write(*,*) 'deallocated'

!        offset = 1
! 
!        do i = 1, pert_tuple%n_perturbations
! 
!           offset = offset + (ind(i) - 1)*product(pert_tuple%pdim &
!                             (i:pert_tuple%n_perturbations))/pert_tuple%pdim(i)
! 
!        end do

    else

       offset = 1

    end if

    found = .FALSE.
    passedlast = 0

    ! NOTE (MaR): WHILE LOOP POTENTIALLY NON-TERMINATING
    ! COULD THIS BE DONE IN ANOTHER WAY?
    do while ((passedlast < 2) .AND. .NOT.(found) .eqv. .TRUE.)

       next_element => sdf_next_element(next_element)

       if (next_element%perturb%n_perturbations == pert_tuple%n_perturbations) then

          if (pert_tuple%n_perturbations == 0) then

             found = .TRUE.

          else

             found = p_tuple_compare(next_element%perturb, pert_tuple)

          end if

       end if

       if (next_element%last .eqv. .TRUE.) then
          passedlast = passedlast + 1
       end if

    end do

    if (found .eqv. .TRUE.) then

! write(*,*) 'size of data', size(next_element%data)

       M = next_element%data(offset)

! write(*,*) 'returning', M%elms(1,1)

    else

       write(*,*) 'Failed to retrieve data in sdf_getdata: Element not found'

    end if

  end subroutine

  ! Get SDF element
  ! Assumes that pert_tuple and the p_tuple in current_element is in standard order
  ! NOTE: NOT UPDATED WITH RESPECT TO TRIANGULAR INDICES
  ! THIS FUNCTION SHOULD BE PHASED OUT AND WILL BE DELETED ONCE CALLS TO IT
  ! HAVE BEEN CONVERTED TO CALLS TO sdf_getdata_s

  function sdf_getdata(current_element, pert_tuple, ind)

    implicit none

    logical :: found
    type(SDF), target :: current_element
    type(SDF), pointer :: next_element
    type(p_tuple) :: pert_tuple
    type(matrix) :: sdf_getdata
    integer, dimension(pert_tuple%n_perturbations) :: ind
    integer :: i, offset, passedlast

    next_element => current_element

    if (pert_tuple%n_perturbations > 0) then

       offset = 1
       
       do i = 1, pert_tuple%n_perturbations

          offset = offset + (ind(i) - 1)*product(pert_tuple%pdim(i: &
                   pert_tuple%n_perturbations))/pert_tuple%pdim(i)
 
       end do

    else

       offset = 1

    end if

    found = .FALSE.
    passedlast = 0

    do while ((passedlast < 2) .AND. .NOT.(found) .eqv. .TRUE.)

       next_element => sdf_next_element(next_element)

       if (next_element%perturb%n_perturbations == pert_tuple%n_perturbations) then

          if (pert_tuple%n_perturbations == 0) then

             found = .TRUE.

          else

             found = p_tuple_compare(next_element%perturb, pert_tuple)

          end if

       end if

       if (next_element%last .eqv. .TRUE.) then
          passedlast = passedlast + 1
       end if

    end do

    if (found .eqv. .TRUE.) then

       sdf_getdata = mat_alloc_like(next_element%data(offset))
       sdf_getdata = mat_zero_like(next_element%data(offset))
       call mat_ensure_alloc(sdf_getdata)

       sdf_getdata = next_element%data(offset)

    else

       write(*,*) 'Failed to retrieve data in sdf_getdata: Element not found'

    end if

  end function


  function sdf_next_element(current_element) result(next_element)

    implicit none

    type(SDF), target :: current_element
    type(SDF), pointer :: next_element

    next_element => current_element%next

  end function


subroutine sdf_reassign_data(current_element, perturbed_matrix_size, data)

type(SDF) :: current_element
integer :: perturbed_matrix_size, i
type(matrix), dimension(perturbed_matrix_size) :: data

    do i = 1, perturbed_matrix_size
    
       current_element%data(i) = mat_alloc_like(data(i))
       current_element%data(i) = mat_zero_like(data(i))
       call mat_ensure_alloc(current_element%data(i))

       current_element%data(i) = data(i)

    end do


end subroutine

  ! Add element routine
  ! NOTE(MaR): This routine assumes that the pert_tuple and data
  ! is already in standard order

  subroutine sdf_add(current_element, pert_tuple, perturbed_matrix_size, data) 

    implicit none

    logical :: found_element
    integer :: passedlast, i, perturbed_matrix_size
    type(SDF), target :: current_element
    type(SDF), pointer :: new_element
    type(SDF), pointer :: new_element_ptr
    type(SDF), pointer :: next_element
    type(p_tuple) :: pert_tuple, p_tuple_st_order
    type(matrix), dimension(perturbed_matrix_size) :: data

    if (sdf_already(current_element, pert_tuple) .eqv. .TRUE.) then

       next_element => current_element
       passedlast = 0
       p_tuple_st_order = p_tuple_standardorder(pert_tuple)
       found_element = .FALSE.

       ! NOTE (MaR): WHILE LOOP POTENTIALLY NON-TERMINATING
       ! COULD THIS BE DONE IN ANOTHER WAY?
       do while ((passedlast < 2) .AND. (found_element .eqv. .FALSE.))

          next_element => sdf_next_element(next_element)
          found_element = p_tuple_compare(next_element%perturb, p_tuple_st_order)

          if (next_element%last .eqv. .TRUE.) then
             passedlast = passedlast + 1
          end if

       end do

call sdf_reassign_data(next_element, perturbed_matrix_size, data)

!        next_element%data = data

    else

       next_element => current_element
       allocate(new_element)
       call sdf_init(new_element, pert_tuple, perturbed_matrix_size, data)
       new_element_ptr => new_element

       ! NOTE (MaR): WHILE LOOP POTENTIALLY NON-TERMINATING
       ! COULD THIS BE DONE IN ANOTHER WAY?
       do while (next_element%last .eqv. .FALSE.)
          next_element => sdf_next_element(next_element)
       end do

       next_element%last = .FALSE.
       new_element%next => next_element%next
       next_element%next => new_element

! call sdf_reassign_data(new_element, perturbed_matrix_size, data)

    end if

  end subroutine


  function sdf_already(current_element, pert_tuple)

    implicit none

    logical :: sdf_already
    type(SDF), target :: current_element
    type(SDF), pointer :: next_element
    type(p_tuple) :: pert_tuple, p_tuple_st_order
    integer :: passedlast

    next_element => current_element

    passedlast = 0
    
    p_tuple_st_order = p_tuple_standardorder(pert_tuple)

    sdf_already = .FALSE.

    ! NOTE (MaR): WHILE LOOP POTENTIALLY NON-TERMINATING
    ! COULD THIS BE DONE IN ANOTHER WAY?
    do while ((passedlast < 2) .AND. (sdf_already .eqv. .FALSE.))

       next_element => sdf_next_element(next_element)
       sdf_already = p_tuple_compare(next_element%perturb, p_tuple_st_order)

       if (next_element%last .eqv. .TRUE.) then
          passedlast = passedlast + 1
       end if

    end do

  end function

end module