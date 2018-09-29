program tsunami

  ! Tsunami simulator
  !
  ! Solves the non-linear 2-d shallow water equation system:
  !
  !     du/dt + u du/dx + v du/dy + g dh/dx = 0
  !     dv/dt + u dv/dx + v dv/dy + g dh/dy = 0
  !     dh/dt + d(hu)/dx + d(hv)/dy = 0
  !
  ! This version is parallelized.

  use iso_fortran_env, only: output_unit

  use mod_boundary, only: reflective_boundary
  use mod_diagnostics, only: ke, mean
  use mod_diff, only: diffx => diffc_2d_x, diffy => diffc_2d_y
  use mod_io, only: write_field
  use mod_kinds, only: ik, rk
  use mod_parallel, only: num_tiles, tile_indices, tile_neighbors_2d

  implicit none

  integer(ik) :: i, j, n

  integer(ik), parameter :: im = 100 ! grid size in x
  integer(ik), parameter :: jm = 100 ! grid size in y
  integer(ik), parameter :: nm = 1000 ! number of time steps

  real(rk), parameter :: dt = 0.02 ! time step [s]
  real(rk), parameter :: dx = 1 ! grid spacing [m]
  real(rk), parameter :: dy = 1 ! grid spacing [m]

  real(rk), parameter :: g = 9.8 ! gravitational acceleration [m/s]

  real(rk), allocatable :: h(:,:)[:], u(:,:)[:], v(:,:)[:]
  !real(rk), allocatable :: h(:,:), u(:,:), v(:,:)
  real(rk), allocatable :: gather(:,:)[:]
  !real(rk), allocatable :: gather(:,:)
  real(rk), allocatable :: hmean(:,:)

  integer(ik), parameter :: ipos = 51, jpos = 51
  real(rk), parameter :: decay = 0.02

  integer(ik), dimension(2) :: indices, neighbors
  integer(ik) :: left, right

  integer(ik) :: is, ie ! global start and end indices
  integer(ik) :: ils, ile ! local start and end computational indices
  integer(ik) :: ims, ime ! local start and end memory indices

  integer(ik) :: js, je ! global start and end indices
  integer(ik) :: jls, jle ! local start and end computational indices
  integer(ik) :: jms, jme ! local start and end memory indices

  integer(ik) :: tile_size

  integer(ik) :: ix(2), iy(2), tiles(2)
  integer(ik) :: itile, jtile

  if (this_image() == 1) print *, 'Tsunami started'

  !neighbors = tile_neighbors()
  !left = neighbors(1)
  !right = neighbors(2)

  !indices = tile_indices(im, this_image(), num_images())
  !is = indices(1)
  !ie = indices(2)

  ! tile layout in 2-d
  tiles = num_tiles(num_images())
  jtile = (this_image() - 1) / tiles(1) + 1
  itile = this_image() - (jtile - 1) * tiles(1)

  if (this_image() == 1) print *, 'Using', tiles(1), 'by', tiles(2), 'parallel tiles'

  sync all
  !print *, 'Image', this_image(), 'has tile position', itile, jtile
  sync all

  print *, 'Tile neighbors:', itile, jtile, tile_neighbors_2d(periodic=.true.)
  sync all
  stop

  ix = tile_indices(im, itile, tiles(1))
  iy = tile_indices(jm, jtile, tiles(2))

  print *, 'Image', this_image(), 'ix, iy', ix, iy
  stop

  tile_size = im / num_images()
  ils = 1
  ile = tile_size
  ims = ils - 1
  ime = ile + 1

  js = is
  je = ie
  jms = ims
  jme = ime
  jls = ils
  jle = ile

  allocate(h(ims:ime, jms:jme)[*])
  allocate(u(ims:ime, jms:jme)[*])
  allocate(v(ims:ime, jms:jme)[*])
  allocate(hmean(ims:ime, jms:jme))

  allocate(gather(im, jm)[*])

  ! initialize a gaussian blob centered at i = 25
  do concurrent(i = is-1:ie+1, j = js-1:je+1)
    h(i-is+1, j-js+1) = exp(-decay * ((i - ipos)**2 + (j - jpos)**2))
  end do

  ! set initial velocity and mean water depth
  u = 0
  v = 0
  hmean = 10

  ! gather to image 1 and write current state to screen
  !gather(is:ie, js:je)[1] = h(ils:ile, jls:jle)
  !sync all
  !if (this_image() == 1) write(unit=output_unit, fmt=*) 0, gather

  time_loop: do n = 1, nm

    ! update halo for h
    !h(ime,:)[left] = h(ils,:)
    !h(ims,:)[right] = h(ile,:)
    !h(:,jme)[left] = h(:,jls)
    !h(:,jms)[right] = h(:,jle)
    !sync all

    ! compute u at next time step
    u = u - (u * diffx(u) / dx&
           + v * diffy(u) / dy&
           + g * diffx(h) / dx) * dt

    v = v - (u * diffx(v) / dx&
           + v * diffy(v) / dy&
           + g * diffy(h) / dy) * dt

    !sync all

    ! update halo for u
    !u(ime,:)[left] = u(ils,:)
    !u(ims,:)[right] = u(ile,:)
    !u(:,jme)[left] = u(:,jls)
    !u(:,jms)[right] = u(:,jle)

    ! update halo for v
    !v(ime,:)[left] = v(ils,:)
    !v(ims,:)[right] = v(ile,:)
    !v(:,jme)[left] = v(:,jls)
    !v(:,jms)[right] = v(:,jle)
    !sync all

    ! compute h at next time step
    h = h - diffx(u * (hmean + h)) / dx * dt&
          - diffy(v * (hmean + h)) / dy * dt

    call reflective_boundary(u, v, h)

    ! gather to image 1 and write current state to screen
    !gather(is:ie)[1] = h(ils:ile)
    !sync all
    !if (this_image() == 1) write(unit=output_unit, fmt=*) n, gather

    !print *, n, h(50, 20), u(50, 20), v(50, 20)
    print *, n, mean(h), mean(ke(u, v))

    call write_field(h, 'h', n)
    call write_field(u, 'u', n)
    call write_field(v, 'v', n)

  end do time_loop

end program tsunami
