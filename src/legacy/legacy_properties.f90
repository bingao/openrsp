!> @file
!> Contains module prop_test

!> ajt/radovan: Response-related testing routines and some calculations
module legacy_properties

   use matrix_defop
   use matrix_lowlevel
   use legacy_property_contributions
   use rsp_equations_old
   use interface_io
   use interface_1el
   use interface_2el
   use interface_rsp_solver
   use interface_nuclear
   use rsp_contribs

   implicit none

   public vcd_aat
   public test_mcd
   public elec_dipmom
   public elec_polariz
   public elec_hypolar
   public alt_elec_hypol
   public elec_sechyp
   public alt_elec_sechyp
   public alt2_elec_sechyp
   public magnetizability
   public elec_quadrupole
   public prop_test_gradient

   private

   !physical constants for conversion to non-atomic units
   real(8), parameter:: cm1 = 1/219474.631371d0, & !1 centimeter-to-minus-one in au
                        cvl = 137.03599907d0,    & !c-the-velocity-of-light in au
                        nm  = 10/0.52917706d0,   & !1 nanometer in au
                        pi  = 3.14159265358979323846D0 !acos(-1.d0)

   !field component lables for printing
   character*2:: fc(3) = (/'Fx','Fy','Fz'/), &
                 bc(3) = (/'Bx','By','Bz'/)

contains

   subroutine vcd_aat(ng, S, D, F)
   ! "Atomic axial tensor" = -1/2 * Egbw
   ! Egbw = << GEO(0.0) MAG(0.0) FREQ(91) >>

      integer,      intent(in) :: ng
      type(matrix), intent(in) :: S, D, F

      complex(8)    :: aat(ng, 3), temp(ng, 3)
      real(8)       :: temp_real(3, ng)

      type(matrix)  :: Db(3), Fb(3), Dbw(3), Fbw(3)
      type(matrix)  :: Wbw(3)
      type(matrix)  :: T, X(1), M(1), SL

      integer       :: ib, ig
      character(1), parameter :: xyz(3) = (/'X','Y','Z'/)

    integer, dimension(0) :: noc
    character(4), dimension(0) :: nof

      call pert_dens(S, (/'MAG'/), (/3/), &
                     (/D/), (/F/), Db, Fb, freq=(/(0d0,0d0)/))
      Fb = 0

      call mat_zero_like(D, SL)
      call mat_zero_like(D, X(1))
      do ib = 1, 3
         call legacy_read_integrals('d<S|/dB'//xyz(ib), SL)

         ! SL - SR
         Fbw(ib) = 0.5d0*SL + 0.5d0*trans(SL) ! SL - SR

         ! form RHS = -S*D*SL - SR*D*S - S*Db*S
         M(1) = -S*D*SL
         M(1) = M(1) - trans(M(1))
         M(1) = M(1) - S*Db(ib)*S

         call rsp_solver_exec(M(1), (/0.0d0/), X(1))

         Dbw(ib) = D*S*X(1) - X(1)*S*D
         call rsp_twoint(S%nrow, 0, nof, noc, noc, Dbw(ib), 1, Fbw(ib))
      end do
      X = 0
      M = 0
      SL = 0

      do ib = 1, 3
         Wbw(ib) = Dbw(ib)*F*D + D*Fbw(ib)*D + D*F*Dbw(ib) &
                 + 0.5d0*Db(ib)*S*D - 0.5d0*D*S*Db(ib)
      end do
      Fbw = 0

      ! contract the frequency-differentiated response function
      aat = 0.0d0

      call mat_zero_like(D, T)
      do ig = 1, ng
         call legacy_read_integrals('SQHDR'//prefix_zeros(ig, 3), T)
         do ib = 1, 3
            aat(ig, ib) = aat(ig, ib) + 0.5d0*dot(Db(ib), T) - 0.5d0*trace(Db(ib), T)
            aat(ig, ib) = aat(ig, ib) + dot(Wbw(ib), T) + trace(Wbw(ib), T)
         end do
      end do
      Wbw = 0
      Db = 0
      do ig = 1, ng
         do ib = 1, 3
            call legacy_read_integrals(prefix_zeros(ig, 2)//' HDB '//xyz(ib), T)
            aat(ig, ib) = aat(ig, ib) + trace(T, D) + dot(T, D)
         end do
      end do
      T = 0

      ! nuclear contribution
      temp_real = 0.0d0
      call aatnuc_ifc(ng/3, temp_real)
      do ib = 1, 3
         do ig = 1, ng
            aat(ig, ib) = aat(ig, ib) - 2.0d0*temp_real(ib, ig)
         end do
      end do

      temp = 0.0d0
      do ib = 1, 3
         call rsp_oneave(1, (/'GEO '/), (/1/), (/ng/), Dbw(ib), 1, (/1, 1, ng/), (/ng/), ng, temp(1, ib))
      end do
      aat = aat + temp

      temp = 0.0d0
      do ib = 1, 3
         call rsp_twoave(1, (/'GEO '/), (/1/), (/ng/), D, Dbw(ib), ng, temp(1, ib))
      end do
      aat = aat + temp

      Dbw = 0

      aat = -0.5d0*aat
      call print_tensor(shape(aat), aat, 'AAT')

   end subroutine



   subroutine test_mcd(S, D, F)
      type(matrix),      intent(in) :: S, D, F
      complex(8)   :: exci(2), Ebfx(3,3,2)
      type(matrix) :: Df(3), Dx(2), Dfx(3,2), DFDfx(3,2)
      type(matrix) :: Ff(3), Fx(2), Ffx(3,2)
      integer      :: i, j, k
      ! find degenerate excitation
      do i = num_solved_eqs-1, 0, -1
         if (i == 0) exit
         if (solved_eqs(i  )%order /= 1) cycle
         if (solved_eqs(i+1)%order /= 1) cycle
         if (solved_eqs(i  )%pert(1) /= 'EXCI') cycle
         if (solved_eqs(i+1)%pert(1) /= 'EXCI') cycle
         if (abs(solved_eqs(i  )%freq(1) &
               - solved_eqs(i+1)%freq(1)) >= 1d-5) cycle
         exci(2) = -solved_eqs(i  )%freq(1)
         exci(1) = -solved_eqs(i+1)%freq(1)
         exit
      end do
      if (i==0) then
         print *, 'no degenerate excited states found'
         return
      end if
      print *, 'found degenerate excitations: ', real(exci(1)), real(exci(2))
      call pert_dens(S, (/'EL'/), (/3/), &
                     (/D/), (/F/), Df, Ff, freq=(/-(exci(1)+exci(2))/2/))
      call pert_dens(S, (/'EXCI'/), (/1/), &
                     (/D/), (/F/), Dx(1:1), Fx(1:1), freq=exci(1:1))
      call pert_dens(S, (/'EXCI'/), (/1/), &
                     (/D/), (/F/), Dx(2:2), Fx(2:2), freq=exci(2:2))
      call pert_dens(S, (/'EL  ','EXCI'/), (/3,1/), &
                     (/D,Df,Dx(1:1)/), (/F,Ff,Fx(1:1)/),    &
                     Dfx(:,1), Ffx(:,1), freq=(/-exci(1),exci(1)/))
      call pert_dens(S, (/'EL  ','EXCI'/), (/3,1/), &
                     (/D,Df,Dx(2:2)/), (/F,Ff,Fx(2:2)/),    &
                     Dfx(:,2), Ffx(:,2), freq=(/-exci(2),exci(2)/))
      ! contract no-London response function
      Ebfx(:,:,:) = 0
      call prop_oneave(S, (/'MAGO'/), (/Dfx/), shape(Ebfx), Ebfx)
      ! call print_tensor(shape(Ebfx), Ebfx, 'E1bDfx - i/2TbDfx - SbDFDfx'); Ebfx=0
      call print_tensor(shape(Ebfx), -Ebfx, 'London d/db alphax = -Ebfx', &
                        (/0*exci(1),-exci(1),exci(1)/))
      ! contract London response function
      Ebfx(:,:,:) = 0
      call prop_oneave(S, (/'MAG','EL '/), (/Dx/), shape(Ebfx), Ebfx)
      ! call print_tensor(shape(Ebfx), Ebfx, 'E1fbDx'); Ebfx=0
      call prop_twoave((/'MAG'/), (/D,Df,Dx,Dfx/), shape(Ebfx), Ebfx)
      ! call print_tensor(shape(Ebfx), Ebfx, 'E2bDfDx+E2bD0Dfx'); Ebfx=0
      do k = 1, 2
         do j = 1, 3
            DFDfx(j,k) = D*Ff(j)*Dx(k) + Df(j)*Fx(k)*D &
                       + Dx(k)*Ff(j)*D + D*Fx(k)*Df(j) &
                       + Df(j)*(F+(-2*exci(k))/2*S)*Dx(k) &
                       + Dx(k)*(F-(-2*exci(k))/2*S)*Df(j) &
                       + Dfx(j,k)*(F+(0*exci(k))/2*S)*D + D*Ffx(j,k)*D &
                       + D*(F-(0*exci(k))/2*S)*Dfx(j,k)
         end do
      end do
      call prop_oneave(S, (/'MAG'/), (/Dfx/), shape(Ebfx), Ebfx, &
                       freq=(/(0d0,0d0)/), DFD=(/DFDfx/))
      DFDfx = 0
      ! call print_tensor(shape(Ebfx), Ebfx, 'E1bDfx - i/2TbDfx - SbDFDfx'); Ebfx=0
      call print_tensor(shape(Ebfx), -Ebfx, 'London d/db alphax = -Ebfx', &
                        (/0*exci(1),-exci(1),exci(1)/))
      Df=0; Ff=0; Dx=0; Fx=0; Dfx=0; Ffx=0
   end subroutine



   subroutine prop_test_gradient(S, D, F, ng)
      type(matrix), intent(in) :: S, D, F
      integer,      intent(in) :: ng !number of geometrical coordinates
      complex(8)   :: Eg(ng) !NB: zero first
      type(matrix) :: DFD

      ! contract first-order geometry-differentiated integrals
      ! with unperturbed density D and energy-weighted density DFD
      DFD = D*F*D
      Eg = 0 !zero first, since prop_one/twoave are incremental
      call prop_oneave(S, (/'GEO'/), (/D/), (/ng/), Eg, DFD=(/DFD/))
      call prop_twoave((/'GEO'/), (/D/), (/ng/), Eg)
      ! print
      call print_tensor((/ng/), Eg, 'gradient = Eg = E0g - Sg DFD')
      ! free DFD
      DFD = 0

   end subroutine

   subroutine prop_test_Gprime_Df(S, D, F, idum, freq) !Gprime_Df(-freq)
      type(matrix), intent(in) :: S, D, F
      integer,      intent(in) :: idum    !not used
      complex(8),   intent(in) :: freq(:) !frequency
      complex(8)   :: Efb(3,3) = 0
      type(matrix) :: Df(3), Ff(3), DFDf(3)
      integer      :: i, j
      ! the following contribution is zero
      ! call prop_oneave(S, (/'EL ','MAG'/), (/D/), shape(Efb), Efb)
      ! solve EL response equations for the negative frequency
      call pert_dens(S, (/'EL'/), shape(Df), (/D/), (/F/), &
                     Df, Ff, freq=-freq(1:1))
      ! compute the EL-perturbed energy-weighted density matrices,
      ! to be contracted against MAG-perturbed overlap integrals
      do i = 1, 3
         DFDf(i) = Df(i)*(F - freq(1)/2*S)*D + D*Ff(i)*D &
                     + D*(F + freq(1)/2*S)*Df(i)
      end do
      ! contract Df and DFDf with MAG-perturbed integrals
      call prop_oneave(S, (/'MAG'/), (/Df/), shape(Efb), Efb, &
                       perm=(/2,1/), freq=freq(1:1), DFD=DFDf)
      call prop_twoave((/'MAG'/), (/D,Df/), shape(Efb), Efb, perm=(/2,1/))
      ! print
      call print_tensor(shape(Efb), Efb, 'G-prime = Efb = E1b Df - Sb DFDf')
      ! free Df(:), Ff(:), DFDf(:)
      Df=0; Ff=0; DFDf=0
   end subroutine


   subroutine prop_test_Gprime_Db(S, D, F, idum, freq) !Gprime_Db(+freq)
      type(matrix),      intent(in) :: S, D, F
      integer,           intent(in) :: idum    !not used
      complex(8),        intent(in) :: freq(:) !frequency
      complex(8)   :: Efb(3,3) = 0
      type(matrix) :: Db(3), Fb(3)
      integer      :: i
      ! the following contribution is zero
      call prop_oneave(S, (/'EL ','MAG'/), (/D/), shape(Efb), Efb)
      ! solve EL response equations for the negative frequency
      call pert_dens(S, (/'MAG'/), shape(Db), (/D/), (/F/), &
                     Db, Fb, freq=freq(1:1))
      ! contract Db with -dipole integrals
      call prop_oneave(S, (/'EL'/), (/Db/), shape(Efb), Efb)
      ! print
      call print_tensor(shape(Efb), Efb, 'G-prime = Efb = E1f Db')
      ! free
      Db = 0;  Fb = 0
   end subroutine


   subroutine elec_dipmom(S, D, F, Ef)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(out) :: Ef(3)
      Ef = 0
      call prop_oneave(S, (/'EL'/), (/D/), (/3/), Ef)
      call print_tensor((/3/), -Ef, 'mu = -Ef', unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3/), -Ef, 'mu = -Ef')
   end subroutine


   subroutine elec_quadrupole(S, D, F, t)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(out) :: t(6)
      t = 0.0d0
      call prop_oneave(S, (/'ELGR'/), (/D/), (/6/), t)
      call print_tensor((/6/), -t, 'quadrupole = -t')
   end subroutine


   subroutine elec_polariz(S, D, F, freq, Eff)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(in)  :: freq
      complex(8),        intent(out) :: Eff(3,3)
      type(matrix) :: Df(3), Ff(3)
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=(/freq/))
      Eff = 0 !zero, as prop_oneave works incrementally
      call prop_oneave(S, (/'EL'/), (/Df/), (/3,3/), Eff)
      call print_tensor((/3,3/), -Eff, 'alpha = -Eff', unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3/), -Eff, 'alpha = -Eff')
      !delete response matrices
      Df = 0; Ff = 0
      !change sign, since polarizability is minus quasi-energy derivative
      Eff = -Eff
   end subroutine


   subroutine elec_hypolar(S, D, F, freq, Efff)
      type(matrix),      intent(in)   :: S, D, F
      complex(8),        intent(in)   :: freq(3)
      complex(8),        intent(out)  :: Efff(3,3,3)
      type(matrix) :: Df(3), De(3), Dfe(3,3)
      type(matrix) :: Ff(3), Fe(3), Ffe(3,3)
      integer      :: i, j
      if (abs(sum(freq)) > 1d-15) &
         call quit('prop_test/elec_hypolar: sum(freq) should be zero!',-1)
      !solve equations
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=freq(2:2))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), De, Fe, freq=freq(3:3))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,Df,De/), (/F,Ff,Fe/), &
                     Dfe, Ffe, freq=(/freq(2),freq(3)/))
      !just one energy contribution, no reort or multiplier contributions
      Efff=0
      call prop_oneave(S, (/'EL'/), (/Dfe/), (/3,3,3/), Efff)
      !print
      call print_tensor((/3,3,3/), -Efff, 'beta = -Efff', freq, unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3,3/), -Efff, 'beta = -Efff', freq)
      !free
      Df=0; Ff=0; De=0; Fe=0; Dfe=0; Ffe=0
      !change sign to get beta
      Efff = -Efff
   end subroutine


   subroutine alt_elec_hypol(S, D, F, freq, Efff)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(in)  :: freq(3)
      complex(8),        intent(out) :: Efff(3,3,3)
      type(matrix) :: De(3), Df(3), Dg(3), DeSD(3), FDSfg
      type(matrix) :: Fe(3), Ff(3), Fg(3), FeDS(3), DSDfg, zm
      character(4) :: UNP(0)
      integer      :: i, j, k
      if (abs(sum(freq)) > 1d-15) &
         call quit('prop_test/alt_elec_hypol: sum(w) should be zero!',-1)
      !solve equations
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=freq(1:1))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), De, Fe, freq=freq(2:2))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dg, Fg, freq=freq(3:3))
      !no energy contributions for HF, one for KSDFT
      Efff = 0
      zm = 0*D
      call prop_twoave(UNP, (/D,De,Df,Dg,(zm,i=1,54)/), (/3,3,3/), Efff)
      !gradient Lagrange multiplier contribution -tr (DeSD-) (FDS-)fg
      do i = 1, 3
         DeSD(i) = De(i)*S*D - D*S*De(i)
      end do
      do k = 1, 3
         do j = 1, 3
            FDSfg = (Ff(j)*Dg(k) + Fg(k)*Df(j)) * S &
              - S * (Df(j)*Fg(k) + Dg(k)*Ff(j))
            do i = 1, 3
               Efff(i,j,k) = Efff(i,j,k) - trace(DeSD(i),FDSfg)
            end do; FDSfg=0
         end do
      end do; DeSD=0
      !idempotency Lagrange multiplier contribution -tr (FeDS+) (DSD)fg
      do i = 1, 3
         FeDS(i) = Fe(i)*D*S + S*D*Fe(i) - Fe(i)
      end do
      do k = 1, 3
         do j = 1, 3
            DSDfg = Df(j)*S*Dg(k) + Dg(k)*S*Df(j)
            do i = 1, 3
               Efff(i,j,k) = Efff(i,j,k) - trace(FeDS(i),DSDfg)
            end do; DSDfg=0
         end do
      end do; FeDS=0
      !print
      call print_tensor((/3,3,3/), -Efff, 'beta = -Efff', freq, unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3,3/), -Efff, 'beta = -Efff', freq)
      !free
      De=0; Fe=0; Df=0; Ff=0; Dg=0; Fg=0
      !change sign for beta
      Efff = -Efff
   end subroutine


   subroutine elec_sechyp(S, D, F, freq, Effff)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(in)  :: freq(4)
      complex(8),        intent(out) :: Effff(3,3,3,3)
      type(matrix) :: De(3), Df(3), Dg(3), Def(3,3),   &
                      Fe(3), Ff(3), Fg(3), Fef(3,3),   &
                      Deg(3,3), Dfg(3,3), Defg(3,3,3), &
                      Feg(3,3), Ffg(3,3), Fefg(3,3,3)
      if (abs(sum(freq)) > 1d-15) &
         call quit('prop_test/elec_sechyp: sum(freq) should be zero!',-1)
      !solve equations
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), De, Fe, freq=(/freq(2)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=(/freq(3)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dg, Fg, freq=(/freq(4)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,De,Df/), (/F,Fe,Ff/), &
                     Def, Fef, freq=(/freq(2),freq(3)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,De,Dg/), (/F,Fe,Fg/), &
                     Deg, Feg, freq=(/freq(2),freq(4)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,Df,Dg/), (/F,Ff,Fg/), &
                     Dfg, Ffg, freq=(/freq(3),freq(4)/))
      call pert_dens(S, (/'EL','EL','EL'/), (/3,3,3/), &
                     (/D,De,Df,Dg,Def,Deg,Dfg/), &
                     (/F,Fe,Ff,Fg,Fef,Feg,Ffg/), &
                     Defg, Fefg, freq=(/freq(2),freq(3),freq(4)/))
      !just one property contribution
      Effff=0
      call prop_oneave(S, (/'EL'/), (/Defg/), (/3,3,3,3/), Effff)
      !print
      call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq, unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq)
      !free
      De=0; Df=0; Dg=0; Def=0; Deg=0; Dfg=0; Defg=0
      Fe=0; Ff=0; Fg=0; Fef=0; Feg=0; Ffg=0; Fefg=0
      !change sign to get gamma
      Effff = -Effff
   end subroutine


   subroutine alt_elec_sechyp(S, D, F, freq, Effff)
      type(matrix), intent(in)  :: S, D, F
      complex(8),   intent(in)  :: freq(4)
      complex(8),   intent(out) :: Effff(3,3,3,3)
      type(matrix) :: De(3), Df(3), Dg(3), Dh(3), DeSD(3), &
                      Dfg(3,3), Dfh(3,3), Dgh(3,3), FDSfgh, &
                      Fe(3), Ff(3), Fg(3), Fh(3), FeDS(3), &
                      Ffg(3,3), Ffh(3,3), Fgh(3,3), DSDfgh, zm
      character(4) :: UNP(0)
      integer      :: i, j, k, l
      if (abs(sum(freq)) > 1d-15) &
         call quit('prop_test/alt_elec_sechyp: sum(w) should be zero!',-1)
      !solve equations
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), De, Fe, freq=(/freq(1)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=(/freq(2)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dg, Fg, freq=(/freq(3)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dh, Fh, freq=(/freq(4)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,Df,Dg/), (/F,Ff,Fg/), &
                     Dfg, Ffg, freq=(/freq(2),freq(3)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,Df,Dh/), (/F,Ff,Fh/), &
                     Dfh, Ffh, freq=(/freq(2),freq(4)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,Dg,Dh/), (/F,Fg,Fh/), &
                     Dgh, Fgh, freq=(/freq(3),freq(4)/))
      ! one energy contribution
      Effff=0
      zm = 0*D
      call prop_twoave(UNP, (/D,De,Df,Dg,Dh, &
                              (zm,i=1,18),Dfg,(zm,i=1,9), &
                              Dfh,Dgh,(zm,i=1,189)/), &
                       shape(Effff), Effff)
      ! gradient Lagrange multiplier contribution -tr (DeSD-) (FDS-)fgh
      do i = 1, 3
         DeSD(i) = De(i)*S*D - D*S*De(i)
      end do
      do l = 1, 3
         do k = 1, 3
            do j = 1, 3
               FDSfgh = (Ff(j)*Dgh(k,l) + Fg(k)*Dfh(j,l) &
                      +  Fh(l)*Dfg(j,k) + Ffg(j,k)*Dh(l) &
                      +  Ffh(j,l)*Dg(k) + Fgh(k,l)*Df(j)) * S &
                  - S * (Df(j)*Fgh(k,l) + Dg(k)*Ffh(j,l) &
                      +  Dh(l)*Ffg(j,k) + Dfg(j,k)*Fh(l) &
                      +  Dfh(j,l)*Fg(k) + Dgh(k,l)*Ff(j))
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(DeSD(i),FDSfgh)
               end do; FDSfgh=0
            end do
         end do
      end do; DeSD=0
      ! idempotency Lagrange multiplier contribution -tr (FhDS+) (DSD)efg
      do i = 1, 3
         FeDS(i) = Fe(i)*D*S + S*D*Fe(i) - Fe(i)
      end do
      do l = 1, 3
         do k = 1, 3
            do j = 1, 3
               DSDfgh = Df(j)*S*Dgh(k,l) + Dg(k)*S*Dfh(j,l) &
                      + Dh(l)*S*Dfg(j,k) + Dfg(j,k)*S*Dh(l) &
                      + Dfh(j,l)*S*Dg(k) + Dgh(k,l)*S*Df(j)
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(FeDS(i),DSDfgh)
               end do; DSDfgh=0
            end do
         end do
      end do; FeDS=0
      ! print
      call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq, unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq)
      !free
      De=0; Df=0; Dg=0; Dh=0; Dfg=0; Dfh=0; Dgh=0
      Fe=0; Ff=0; Fg=0; Fh=0; Ffg=0; Ffh=0; Fgh=0
      !change sign to get gamma
      Effff = -Effff
   end subroutine


   subroutine alt2_elec_sechyp(S, D, F, freq, Effff)
      type(matrix),      intent(in)  :: S, D, F
      complex(8),        intent(in)  :: freq(4)
      complex(8),        intent(out) :: Effff(3,3,3,3)
      type(matrix) :: De(3), Df(3), Dg(3), Dh(3), DSD,      &
                      Fe(3), Ff(3), Fg(3), Fh(3), FDS,      &
                      Def(3,3), Deg(3,3), Deh(3,3),         &
                      Fef(3,3), Feg(3,3), Feh(3,3),         &
                      DeSDf(3,3), FDSgh, FeDSf(3,3), DSDgh, &
                      DeSDg(3,3), FDSfh, FeDSg(3,3), DSDfh, &
                      DeSDh(3,3), FDSfg, FeDSh(3,3), DSDfg
      integer      :: i, j, k, l
      if (abs(sum(freq)) > 1d-15) &
         call quit('prop_test/alt_elec_sechyp: sum(freq) should be zero!',-1)
      !solve equations
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), De, Fe, freq=(/freq(1)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Df, Ff, freq=(/freq(2)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dg, Fg, freq=(/freq(3)/))
      call pert_dens(S, (/'EL'/), (/3/), (/D/), (/F/), Dh, Fh, freq=(/freq(4)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,De,Df/), (/F,Fe,Ff/), &
                     Def, Fef, freq=(/freq(1),freq(2)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,De,Dg/), (/F,Fe,Fg/), &
                     Deg, Feg, freq=(/freq(1),freq(3)/))
      call pert_dens(S, (/'EL','EL'/), (/3,3/), (/D,De,Dh/), (/F,Fe,Fh/), &
                     Deh, Feh, freq=(/freq(1),freq(4)/))
      !no energy contributions
      Effff=0
      !gradient Lagrange multiplier contribution -tr (DeSD-)f (FDS-)gh
      do j = 1, 3
         do i = 1, 3
            DeSDf(i,j) = Def(i,j)*S*D  - D*S*Def(i,j)  &
                       + De(i)*S*Df(j) - Df(j)*S*De(i)
         end do
      end do
      do l = 1, 3
         do k = 1, 3
            FDSgh = (Fg(k)*Dh(l) + Fh(l)*Dg(k)) * S &
              - S * (Dh(l)*Fg(k) + Dg(k)*Fh(l))
            do j = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(DeSDf(i,j),FDSgh)
               end do
            end do; FDSgh=0
         end do
      end do; DeSDf=0
      !idempotency Lagrange multiplier contribution -tr (FeDS+)f (DSD)gh
      do j = 1, 3
         do i = 1, 3
            FeDSf(i,j) = (Fef(i,j)*D + Fe(i)*Df(j)) * S &
                   + S * (D*Fef(i,j) + Df(j)*Fe(i)) - Fef(i,j)
         end do
      end do
      do l = 1, 3
         do k = 1, 3
            DSDgh = Dg(k)*S*Dh(l) + Dh(l)*S*Dg(k)
            do j = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(FeDSf(i,j),DSDgh)
               end do
            end do; DSDgh=0
         end do
      end do; FeDSf=0
      !gradient Lagrange multiplier contribution -tr (DeSD-)g (FDS-)fh
      do k = 1, 3
         do i = 1, 3
            DeSDg(i,k) = Deg(i,k)*S*D  - D*S*Deg(i,k)  &
                       + De(i)*S*Dg(k) - Dg(k)*S*De(i)
         end do
      end do
      do l = 1, 3
         do j = 1, 3
            FDSfh = (Ff(j)*Dh(l) + Fh(l)*Df(j)) * S &
              - S * (Df(j)*Fh(l) + Dh(l)*Ff(j))
            do k = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(DeSDg(i,k),FDSfh)
               end do
            end do; FDSfh=0
         end do
      end do; DeSDg=0
      !idempotency Lagrange multiplier contribution -tr (FeDS+)g (DSD)fh
      do k = 1, 3
         do i = 1, 3
            FeDSg(i,k) = (Feg(i,k)*D + Fe(i)*Dg(k)) * S &
                   + S * (D*Feg(i,k) + Dg(k)*Fe(i)) - Feg(i,k)
         end do
      end do
      do l = 1, 3
         do j = 1, 3
            DSDfh = Df(j)*S*Dh(l) + Dh(l)*S*Df(j)
            do k = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(FeDSg(i,k),DSDfh)
               end do
            end do; DSDfh=0
         end do
      end do; FeDSg=0
      !gradient Lagrange multiplier contribution -tr (DeSD-)h (FDS-)fg
      do l = 1, 3
         do i = 1, 3
            DeSDh(i,l) = Deh(i,l)*S*D  - D*S*Deh(i,l)  &
                       + De(i)*S*Dh(l) - Dh(l)*S*De(i)
         end do
      end do
      do k = 1, 3
         do j = 1, 3
            FDSfg = (Ff(j)*Dg(k) + Fg(k)*Df(j)) * S &
              - S * (Df(j)*Fg(k) + Dg(k)*Ff(j))
            do l = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(DeSDh(i,l),FDSfg)
               end do
            end do; FDSfg=0
         end do
      end do; DeSDh=0
      !idempotency Lagrange multiplier contribution -tr (FeDS+)h (DSD)fg
      do l = 1, 3
         do i = 1, 3
            FeDSh(i,l) = (Feh(i,l)*D + Fe(i)*Dh(l)) * S &
                   + S * (D*Feh(i,l) + Dh(l)*Fe(i)) - Feh(i,l)
         end do
      end do
      do k = 1, 3
         do j = 1, 3
            DSDfg = Df(j)*S*Dg(k) + Dg(k)*S*Df(j)
            do l = 1, 3
               do i = 1, 3
                  Effff(i,j,k,l) = Effff(i,j,k,l) - trace(FeDSh(i,l),DSDfg)
               end do
            end do; DSDfg=0
         end do
      end do; FeDSh=0
      !print
      call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq, unit=get_print_unit())
      if (get_print_unit() /= 6) call print_tensor((/3,3,3,3/), -Effff, 'gamma = -Effff', freq)
      !free
      De=0; Df=0; Dg=0; Dh=0; Def=0; Deg=0; Deh=0
      Fe=0; Ff=0; Fg=0; Dh=0; Fef=0; Feg=0; Feh=0
      !change sign to get gamma
      Effff = -Effff
   end subroutine


   subroutine magnetizability(S, D, F)
   !no-Lon and London magnetizability
      type(matrix),      intent(in)  :: S, D, F

      complex(8),        parameter   :: freq = 0.0d0
      complex(8)                     :: Eoo(3,3), Ebb(3,3)
      type(matrix) :: Db(3), Fb(3), DFD, DFDb(3)
      integer      :: i, j
      !no-London
      call pert_dens(S, (/'MAGO'/), (/3/), (/D/), (/F/), Db, Fb, freq=(/freq/))
      Eoo = 0
      call prop_oneave(S, (/'MAGO','MAGO'/), (/D/), (/3,3/), Eoo)
      !call print_tensor( (/3,3/), Eoo, 'E0oo'); Eoo=0
      call prop_oneave(S, (/'MAGO'/), (/Db/), (/3,3/), Eoo)
      !call print_tensor( (/3,3/), Eoo, 'E1oDo'); Eoo=0
      call print_tensor((/3,3/), Eoo, 'no-London Magnetizability = Eoo', (/-freq,freq/))
      Db=0; Fb=0
      !London diamag
      call pert_dens(S, (/'MAG'/), (/3/), (/D/), (/F/), Db, Fb, freq=(/freq/))
      Ebb = 0
      call prop_twoave((/'MAG','MAG'/), (/D/), (/3,3/), Ebb)
      DFD = D*F*D
      call prop_oneave(S, (/'MAG','MAG'/), (/D/), (/3,3/), Ebb, &
                       DFD=(/DFD/), freq=(/-freq,freq/))
      DFD = 0
      !call print_tensor( (/3,3/), Ebb, 'E0bb-i/2TbbD-SbbW'); Ebb=0
      !London paramag
      call prop_twoave((/'MAG'/), (/D,Db/), (/3,3/), Ebb)
      do j = 1, 3
         DFDb(j) = Db(j)*(F+(freq/2)*S)*D + D*Fb(j)*D &
                 +     D*(F-(freq/2)*S)*Db(j)
      end do
      call prop_oneave(S, (/'MAG'/), (/Db/), (/3,3/), Ebb, &
                       DFD=DFDb, freq=(/-freq/))
      Db=0; Fb=0; DFDb=0
      !call print_tensor( (/3,3/), Ebb, 'E1bDb-i/2TbDb-SbDFDb'); Ebb=0
      call print_tensor((/3,3/), Ebb, 'London Magnetizability = Ebb', (/-freq,freq/))
   end subroutine


  subroutine test_grcont(n, nr_atoms, test_london, test_geo)

    integer              :: n, nr_atoms
    logical              :: test_london, test_geo
!   ----------------------------------------------------------------------------
    real(8), allocatable :: work(:)
    integer              :: lwork

    integer              :: i, j, k, l, m
    real(8)              :: D(n, n, 2)
    real(8)              :: F(n, n, 3), g(3, nr_atoms)

    lwork = 10000*n + 50*n*n
    allocate(work(lwork))

    if (test_london) then

      print '(a)', 'London 2e integrals'
      print '(a, 12x, a2, 18x, a2, 18x, a2)', '  i  j  k  l', 'Bx', 'By', 'Bz'

!     do l = 1, n
!       do k = 1, n
      do l = 1, 1
        do k = 1, 1

          D(:, :, 1) = 0.0d0
          D(k, l, 1) = 1.0d0
          F          = 0.0d0

          call grcont(work, lwork, F, n*n*3, &
                      .false., .true., 1, 0, .false., .true., D(:, :, 1), 1)
          do j = 1, n
            do i = 1, n
              write(0, '(4i3, 3f20.12)') i, j, k, l, F(i, j, :)
            end do
          end do
        end do
      end do
    end if

    if (test_geo) then

      print '(a)', 'Geometry 2e integrals'
      print '(a, 12x, a2, 18x, a2, 18x, a2)', '  i  j  k  l  a', 'Rx', 'Ry', 'Rz'

      D = 0.0d0

!     do l = 1, n
!       do k = 1, n
      do l = 1, 1
        do k = 1, 1
          do j = 1, n
            do i = 1, n

              D(k, l, 1) = 1.0d0
              D(i, j, 2) = 1.0d0
              g          = 0.0d0

              call grcont(work, lwork, g, 3*nr_atoms, &
                          .true., .false., 1, 0, .true., .false., D, 2)
              D(k, l, 1) = 0.0d0
              D(i, j, 2) = 0.0d0

              do m = 1, nr_atoms
                write(0, '(5i3, 3f20.12)') i, j, k, l, m, g(:, m)
              end do
            end do
          end do
        end do
      end do
    end if

    deallocate(work)

  end subroutine


  subroutine print_tensor(dims, tensor, title, freqs, colwidth, unit)
  !ajt This is used for printing response function tensors
  !TODO: Add comp. lables argument. Make space between blocks of rows
    integer,                intent(in) :: dims(:)
    complex(8),             intent(in) :: tensor(*) !(product(dims))
    character(*), optional, intent(in) :: title
    integer,      optional, intent(in) :: colwidth, unit
    complex(8),   optional, intent(in) :: freqs(:)
    integer     :: uni, siz, dec, cwid, i
    character*9 :: fmt
    uni = 6
    if (present(unit)) uni = unit
    if (present(title)) then
       if (present(freqs)) then
          fmt = '(a,nf8.3)'
          write (fmt(4:4),'(i1)') size(freqs)
          write (uni,fmt) title // ' w:', dreal(freqs)
       else
          write (uni,'(a)') title
       end if
    end if
    siz = product(dims)
    dec = max(2, 1+ceiling(log10(maxval(abs(tensor(1:siz))))))
    !dec = max(dec,ceiling(log10( maxval(tensor(1:siz)))))
    cwid = 15
    if (present(colwidth)) cwid = max(colwidth,dec+2)
    dec = cwid - dec - 1
    fmt = '(fww.dd)'
    write (fmt(3:7),'(i2,a1,i2)') cwid, '.', dec
    if (any(dimag(tensor(1:siz)) /= 0)) write (uni,'(a)') '    (real part)'
    call subr(dims, dreal(tensor(1:siz)), uni, cwid, fmt)
    if (any(dimag(tensor(1:siz)) /= 0)) then
       write (uni,'(a)') '    (imaginary part)'
       call subr(dims, dimag(tensor(1:siz)), uni, cwid, fmt)
    end if
    write (uni,'()') !final blank line
  contains
    subroutine subr(dims, tnz, unit, cwid, fmt)
       integer,     intent(in) :: dims(:), unit, cwid
       real(8),     intent(in) :: tnz(*)
       character*8, intent(in) :: fmt
       integer :: i, j, l
       character*(dims(1)*(cwid+1)) :: line
       do i = 1, product(dims), dims(1)
          l = 1
          do j = 1, dims(1)
             line(l:l) = ' '
             write (line(l+1:l+cwid), fmt) tnz(i+j-1)
             l = l + 1 + cwid
          end do
          write (unit,'(a)') line
       end do
    end subroutine
  end subroutine

  function prefix_zeros(n, l)
    integer, intent(in) :: n, l !number, length
    character(l)        :: prefix_zeros !resulting n in ascii
    character(1), parameter :: char0to9(0:9) &
          = (/'0','1','2','3','4','5','6','7','8','9'/)
    integer :: i, k
    k = n
    do i = l, 1, -1
       prefix_zeros(i:i) = char0to9(mod(k,10))
       k = k / 10
    end do
    if (k /= 0) call quit('prefix_zeros error: Argument integer does not fit ' &
                       // 'in the specified number of ASCII caracters')
  end function


end module