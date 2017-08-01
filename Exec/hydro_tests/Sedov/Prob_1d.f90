subroutine amrex_probinit (init,name,namlen,problo,probhi) bind(c)

  use probdata_module
  use prob_params_module, only : center
  use amrex_fort_module, only : rt => amrex_real
  implicit none

  integer :: init, namlen
  integer :: name(namlen)
  real(rt)         :: problo(1), probhi(1)

  integer :: untin,i

  namelist /fortin/ probtype, p_ambient, dens_ambient, exp_energy, &
           r_init, nsub

  ! Build "probin" filename -- the name of file containing fortin namelist.
  integer, parameter :: maxlen = 256
  character :: probin*(maxlen)

  if (namlen .gt. maxlen) then
     call bl_error('probin file name too long')
  end if

  do i = 1, namlen
     probin(i:i) = char(name(i))
  end do

  ! set namelist defaults

  p_ambient = 1.e-5_rt        ! ambient pressure (in erg/cc)
  dens_ambient = 1.e0_rt      ! ambient density (in g/cc)
  exp_energy = 1.e0_rt        ! absolute energy of the explosion (in erg)
  r_init = 0.05e0_rt          ! initial radius of the explosion (in cm)
  nsub = 4

  ! Read namelists
  untin = 9
  open(untin,file=probin(1:namlen),form='formatted',status='old')
  read(untin,fortin)
  close(unit=untin)

  center(1) = 0.e0_rt

end subroutine amrex_probinit


! ::: -----------------------------------------------------------
! ::: This routine is called at problem setup time and is used
! ::: to initialize data on each grid.
! :::
! ::: NOTE:  all arrays have one cell of ghost zones surrounding
! :::        the grid interior.  Values in these cells need not
! :::        be set here.
! :::
! ::: INPUTS/OUTPUTS:
! :::
! ::: level     => amr level of grid
! ::: time      => time at which to init data
! ::: lo,hi     => index limits of grid interior (cell centered)
! ::: nstate    => number of state components.  You should know
! :::		   this already!
! ::: state     <=  Scalar array
! ::: delta     => cell size
! ::: xlo,xhi   => physical locations of lower left and upper
! :::              right hand corner of grid.  (does not include
! :::		   ghost region).
! ::: -----------------------------------------------------------
subroutine ca_initdata(level,time,lo,hi,nscal, &
                       state,state_l1,state_h1, &
                       delta,xlo,xhi)

  use probdata_module
  use bl_constants_module, only: M_PI, FOUR3RD, ZERO, ONE
  use meth_params_module , only: NVAR, URHO, UMX, UMZ, UEDEN, UEINT, UFS
  use amrex_fort_module, only : rt => amrex_real
  use network, only : nspec
  use eos_module, only : eos
  use eos_type_module, only : eos_t, eos_input_rp, eos_input_re

  implicit none

  integer :: level, nscal
  integer :: lo(1), hi(1)
  integer :: state_l1,state_h1
  real(rt)         :: xlo(1), xhi(1), time, delta(1)
  real(rt)         :: state(state_l1:state_h1,NVAR)

  real(rt)         :: xmin
  real(rt)         :: xx, xl, xr
  real(rt)         :: dx_sub,dist
  real(rt)         :: eint, p_zone
  real(rt)         :: vctr, p_exp

  integer :: i,ii
  real(rt)         :: vol_pert, vol_ambient
  real(rt) :: xn_zone(nspec), e_zone
  type(eos_t) :: eos_state

  xn_zone(:) = ZERO
  xn_zone(1) = ONE

  dx_sub = delta(1)/dble(nsub)

  ! Cylindrical coordinates
  if (probtype .eq. 11) then

     ! set explosion pressure -- we will convert the point-explosion energy into
     ! a corresponding pressure distributed throughout the perturbed volume
     vctr = M_PI*r_init**2

     e_zone = exp_energy/vctr/dens_ambient

     eos_state % e = e_zone
     eos_state % rho = dens_ambient
     eos_state % xn(:) = xn_zone(:)
     eos_state % T = 100.0  ! initial guess

     call eos(eos_input_re, eos_state)

     p_exp = eos_state % p

     do i = lo(1), hi(1)
        xmin = xlo(1) + delta(1)*dble(i-lo(1))
        vol_pert    = 0.e0_rt
        vol_ambient = 0.e0_rt
        do ii = 0, nsub-1
           xx = xmin + (dble(ii) + 0.5e0_rt) * dx_sub
           dist = xx
           if(dist <= r_init) then
              vol_pert = vol_pert + dist
           else
              vol_ambient = vol_ambient + dist
           endif
        enddo

        p_zone = (vol_pert*p_exp + vol_ambient*p_ambient)/(vol_pert+vol_ambient)

        eos_state % p = p_zone
        eos_state % rho = dens_ambient
        eos_state % xn(:) = xn_zone(:)

        call eos(eos_input_rp, eos_state)

        eint = dens_ambient * eos_state % e

        state(i,URHO) = dens_ambient
        state(i,UMX:UMZ) = 0.e0_rt

        state(i,UEDEN) = eint + 0.5e0_rt * state(i,UMX)**2 / state(i,URHO)
        state(i,UEINT) = eint

        state(i,UFS) = state(i,URHO)

     end do

     ! Spherical coordinates
  else if (probtype .eq. 12) then

     ! set explosion pressure -- we will convert the point-explosion energy into
     ! a corresponding pressure distributed throughout the perturbed volume
     vctr = FOUR3RD*M_PI*r_init**3

     e_zone = exp_energy/vctr/dens_ambient

     eos_state % e = e_zone
     eos_state % rho = dens_ambient
     eos_state % xn(:) = xn_zone(:)
     eos_state % T = 100.0  ! initial guess

     call eos(eos_input_re, eos_state)

     p_exp = eos_state % p

     do i = lo(1), hi(1)
        xmin = xlo(1) + delta(1)*dble(i-lo(1))
        vol_pert    = 0.e0_rt
        vol_ambient = 0.e0_rt
        do ii = 0, nsub-1
           xl = xmin + (dble(ii)        ) * dx_sub
           xr = xmin + (dble(ii) + 1.0e0_rt) * dx_sub
           xx = 0.5e0_rt*(xl + xr)

           ! the volume of a subzone is (4/3) pi (xr^3 - xl^3).
           ! we can factor this as: (4/3) pi dr (xr^2 + xl*xr + xl^2)
           ! The (4/3) pi dr factor is common, so we can neglect it.
           if(xx <= r_init) then
              vol_pert = vol_pert + (xr*xr + xl*xr + xl*xl)
           else
              vol_ambient = vol_ambient + (xr*xr + xl*xr + xl*xl)
           endif
        enddo

        p_zone = (vol_pert*p_exp + vol_ambient*p_ambient)/(vol_pert+vol_ambient)

        eos_state % p = p_zone
        eos_state % rho = dens_ambient
        eos_state % xn(:) = xn_zone(:)

        call eos(eos_input_rp, eos_state)

        eint = dens_ambient * eos_state % e

        state(i,URHO) = dens_ambient
        state(i,UMX:UMZ) = 0.e0_rt

        state(i,UEDEN) = eint + 0.5e0_rt * state(i,UMX)**2 / state(i,URHO)
        state(i,UEINT) = eint

        state(i,UFS) = state(i,URHO)

     end do
  else

     call bl_error('dont know this probtype in initdata')

  end if

end subroutine ca_initdata