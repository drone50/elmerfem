!/*****************************************************************************/
! *
! *  Elmer/Ice, a glaciological add-on to Elmer
! *  http://elmerice.elmerfem.org
! *
! * 
! *  This program is free software; you can redistribute it and/or
! *  modify it under the terms of the GNU General Public License
! *  as published by the Free Software Foundation; either version 2
! *  of the License, or (at your option) any later version.
! * 
! *  This program is distributed in the hope that it will be useful,
! *  but WITHOUT ANY WARRANTY; without even the implied warranty of
! *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! *  GNU General Public License for more details.
! *
! *  You should have received a copy of the GNU General Public License
! *  along with this program (in file fem/GPL-2); if not, write to the 
! *  Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, 
! *  Boston, MA 02110-1301, USA.
! *
! *****************************************************************************/
! ******************************************************************************
! *
! *  Authors: Olivier Gagliardini             
! *  Email:   gagliar@lgge.obs.ujf-grenoble.fr
! *  Web:     http://elmerice.elmerfem.org
! *
! *  Original Date: 30. April 2010
! * 
! *****************************************************************************
!> SSolver to inquire the velocity from the SSA solution            
SUBROUTINE SSABasalSolver( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Solve the in-plane basal velocity with the SSA solution !
!  To be computed only at the base. Use then the SSASolver to export verticaly 
!  the basal velocity and compute the vertical velocity and pressure (if needed)
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Nodes_t)   :: ElementNodes
  TYPE(Element_t),POINTER :: CurrentElement, Element, ParentElement, BoundaryElement
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(ValueList_t), POINTER :: SolverParams, BodyForce, Material, BC
  TYPE(Variable_t), POINTER :: PointerToVariable, ZsSol, ZbSol, &
                               VeloSol

  LOGICAL :: AllocationsDone = .FALSE., Found, GotIt, CalvingFront 
  LOGICAL :: Newton

  INTEGER :: i, n, m, t, istat, DIM, p, STDOFs
  INTEGER :: NonlinearIter, NewtonIter, iter, other_body_id
          
  INTEGER, POINTER :: Permutation(:), &
       ZsPerm(:), ZbPerm(:), &
       NodeIndexes(:)

  REAL(KIND=dp), POINTER :: ForceVector(:)
  REAL(KIND=dp), POINTER :: VariableValues(:), Zs(:), Zb(:)
                            
  REAL(KIND=dp) :: UNorm, cn, dd, NonlinearTol, NewtonTol, MinSRInv, rhow, sealevel, &
                   PrevUNorm, relativeChange,minv

  REAL(KIND=dp), ALLOCATABLE :: STIFF(:,:), LOAD(:), FORCE(:), &
           NodalGravity(:), NodalViscosity(:), NodalDensity(:), &
           NodalZs(:), NodalZb(:),   &
           NodalU(:), NodalV(:), NodalSliding(:,:)

  CHARACTER(LEN=MAX_NAME_LEN) :: SolverName
  REAL(KIND=dp) :: at, at0, CPUTime, RealTime
       
  SAVE rhow,sealevel
  SAVE STIFF, LOAD, FORCE, AllocationsDone, DIM, SolverName, ElementNodes
  SAVE NodalGravity, NodalViscosity, NodalDensity, &
           NodalZs, NodalZb,   &
           NodalU, NodalV, NodeIndexes, NodalSliding

!------------------------------------------------------------------------------
  PointerToVariable => Solver % Variable
  Permutation  => PointerToVariable % Perm
  VariableValues => PointerToVariable % Values
  STDOFs = PointerToVariable % DOFs 
  WRITE(SolverName, '(A)') 'SSASolver-SSABasalSolver'

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
        DIM = CoordinateSystemDimension()


        ZbSol => VariableGet( Solver % Mesh % Variables, 'Zb' )
        IF (ASSOCIATED(ZbSol)) THEN
           Zb => ZbSol % Values
           ZbPerm => ZbSol % Perm
        ELSE
           CALL FATAL(SolverName,'Could not find variable >Zb<')
        END IF

        ZsSol => VariableGet( Solver % Mesh % Variables, 'Zs' )
        IF (ASSOCIATED(ZsSol)) THEN
           Zs => ZsSol % Values
           ZsPerm => ZsSol % Perm
        ELSE
           CALL FATAL(SolverName,'Could not find variable >Zs<')
        END IF
  !--------------------------------------------------------------
  !Allocate some permanent storage, this is done first time only:
  !--------------------------------------------------------------
  IF ( (.NOT. AllocationsDone) .OR. Solver % Mesh % Changed  ) THEN

     ! Get some constants
     rhow = GetConstReal( Model % Constants, 'Water Density', Found )
     If (.NOT.Found) Then
            WRITE(Message,'(A)') 'Constant Water Density not found. &
                   &Setting to 1.03225e-18'
            CALL INFO(SolverName, Message, level=20)
            rhow = 1.03225e-18_dp
     End if

     sealevel = GetConstReal( Model % Constants, 'Sea Level', Found )
     If (.NOT.Found) Then
            WRITE(Message,'(A)') 'Constant >Sea Level< not found. &
                   &Setting to 0.0'
            CALL INFO(SolverName, Message, level=20)
            sealevel=0.0_dp
     End if

     ! Allocate

     N = Model % MaxElementNodes
     M = Model % Mesh % NumberOfNodes
     IF (AllocationsDone) DEALLOCATE(FORCE, LOAD, STIFF, NodalGravity, &
                       NodalViscosity, NodalDensity,  &
                       NodalZb, NodalZs,  NodalU, NodalV, &
                       NodalSliding, ElementNodes % x, &
                       ElementNodes % y, ElementNodes % z )

     ALLOCATE( FORCE(STDOFs*N), LOAD(N), STIFF(STDOFs*N,STDOFs*N), &
          NodalGravity(N), NodalDensity(N), NodalViscosity(N), &
          NodalZb(N), NodalZs(N) ,&
          NodalU(N), NodalV(N), NodalSliding(2,N), &
          ElementNodes % x(N), ElementNodes % y(N), ElementNodes % z(N), &
           STAT=istat )
     IF ( istat /= 0 ) THEN
        CALL Fatal( SolverName, 'Memory allocation error.' )
     END IF

     AllocationsDone = .TRUE.
     CALL INFO( SolverName, 'Memory allocation done.',Level=1 )
  END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS

!------------------------------------------------------------------------------
!    Do some additional initialization, and go for it
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
      NonlinearTol = GetConstReal( Solver % Values, &
        'Nonlinear System Convergence Tolerance' )

      NonlinearIter = GetInteger( Solver % Values, &
         'Nonlinear System Max Iterations',GotIt )

      IF ( .NOT.GotIt ) NonlinearIter = 1

      NewtonTol = ListGetConstReal( Solver % Values, &
              'Nonlinear System Newton After Tolerance', minv=0.0d0 )

      NewtonIter = ListGetInteger( Solver % Values, &
              'Nonlinear System Newton After Iterations', GotIt )
      if (.NOT.Gotit) NewtonIter = NonlinearIter + 1

    
      Newton=.False.

!------------------------------------------------------------------------------
      DO iter=1,NonlinearIter

       at  = CPUTime()
       at0 = RealTime()

       CALL Info( SolverName, ' ', Level=4 )
       CALL Info( SolverName, ' ', Level=4 )
       CALL Info( SolverName, &
                   '-------------------------------------',Level=4 )
       WRITE( Message, * ) 'SSA BASAL VELOCITY NON-LINEAR ITERATION', iter
       CALL Info( SolverName, Message, Level=4 )
       If (Newton) Then
           WRITE( Message, * ) 'Newton linearisation is used'
           CALL Info( SolverName, Message, Level=4 )
       Endif
       CALL Info( SolverName, ' ', Level=4 )
       CALL Info( SolverName, &
                   '-------------------------------------',Level=4 )
       CALL Info( SolverName, ' ', Level=4 )


  !Initialize the system and do the assembly:
  !------------------------------------------
  CALL DefaultInitialize()

  ! bulk assembly
  DO t=1,Solver % NumberOfActiveElements
     Element => GetActiveElement(t)
     IF (ParEnv % myPe .NE. Element % partIndex) CYCLE
     n = GetElementNOFNodes()

     NodeIndexes => Element % NodeIndexes

 ! set coords of highest occuring dimension to zero (to get correct path element)
        !-------------------------------------------------------------------------------
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        IF (STDOFs == 1) THEN !1D SSA
           ElementNodes % y(1:n) = 0.0_dp
           ElementNodes % z(1:n) = 0.0_dp
        ELSE IF (STDOFs == 2) THEN !2D SSA
           ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
           ElementNodes % z(1:n) = 0.0_dp
        ELSE
           WRITE(Message,'(a,i1,a)')&
                'It is not possible to compute SSA problems with DOFs=',&
                STDOFs, ' . Aborting'
           CALL Fatal( SolverName, Message)
           STOP
        END IF

     ! Read the gravity in the Body Force Section 
     BodyForce => GetBodyForce()
     NodalGravity = 0.0_dp
     IF ( ASSOCIATED( BodyForce ) ) THEN
           IF (STDOFs==1) THEN 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 2', n, NodeIndexes, Found)
           ELSE 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 3', n, NodeIndexes, Found)
           END IF
     END IF

     ! Read the Viscosity eta, density, and exponent m in MMaterial Section
     ! Same definition as NS Solver in Elmer - n=1/m , A = 1/ (2 eta^n) 
     Material => GetMaterial(Element)

     
     cn = ListGetConstReal( Material, 'Viscosity Exponent',Found)
     MinSRInv = ListGetConstReal( Material, 'Critical Shear Rate',Found)


     NodalDensity=0.0_dp
     NodalDensity(1:n) = ListGetReal( Material, 'SSA Mean Density',n,NodeIndexes,Found)
     IF (.NOT.Found) &
           CALL FATAL(SolverName,'Could not find Material prop.  >SSA Mean Density<')

     NodalViscosity=0.0_dp
     NodalViscosity(1:n) = ListGetReal( Material, 'SSA Mean Viscosity',n, NodeIndexes,Found)
     IF (.NOT.Found) &
          CALL FATAL(SolverName,'Could not find Material prop. >SSA Mean Viscosity<')

     NodalSliding = 0.0_dp
     NodalSliding(1,1:n) = ListGetReal( &
           Material, 'SSA Slip Coefficient 1', n, NodeIndexes(1:n), Found )
     IF (STDOFs==2) THEN
        NodalSliding(2,1:n) = ListGetReal( &
             Material, 'SSA Slip Coefficient 2', n, NodeIndexes(1:n), Found )  
     END IF


     ! Get the Nodal value of Zb and Zs
     NodalZb(1:n) = Zb(ZbPerm(NodeIndexes(1:n)))
     NodalZs(1:n) = Zs(ZsPerm(NodeIndexes(1:n)))

     ! Previous Velocity 
     NodalU(1:n) = VariableValues(STDOFs*(Permutation(NodeIndexes(1:n))-1)+1)
     NodalV = 0.0
     IF (STDOFs.EQ.2) NodalV(1:n) = VariableValues(STDOFs*(Permutation(NodeIndexes(1:n))-1)+2)
      

     CALL LocalMatrixUVSSA (  STIFF, FORCE, Element, n, ElementNodes, NodalGravity, &
        NodalDensity, NodalViscosity, NodalZb, NodalZs, &
        NodalU, NodalV, NodalSliding, cn, MinSRInv , STDOFs, Newton)

     CALL DefaultUpdateEquations( STIFF, FORCE )

  END DO
  CALL DefaultFinishBulkAssembly()
  
!  
! Neumann condition
!
  DO t=1,GetNOFBoundaryElements()
     BoundaryElement => GetBoundaryElement(t)
     IF ( .NOT. ActiveBoundaryElement() ) CYCLE
     IF ( GetElementFamily() == 1 ) CYCLE

     NodeIndexes => BoundaryElement % NodeIndexes
     IF (ParEnv % myPe .NE. BoundaryElement % partIndex) CYCLE

     n = GetElementNOFNodes()
     FORCE = 0.0e0
     STIFF = 0.0e0

 ! set coords of highest occuring dimension to zero (to get correct path element)
        !-------------------------------------------------------------------------------
        ElementNodes % x(1:n) = Solver % Mesh % Nodes % x(NodeIndexes)
        IF (STDOFs == 1) THEN
           ElementNodes % y(1:n) = 0.0_dp
           ElementNodes % z(1:n) = 0.0_dp
        ELSE IF (STDOFs == 2) THEN
           ElementNodes % y(1:n) = Solver % Mesh % Nodes % y(NodeIndexes)
           ElementNodes % z(1:n) = 0.0_dp
        ELSE
           WRITE(Message,'(a,i1,a)')&
                'It is not possible to compute SSA with SSA var DOFs=',&
                STDOFs, '. Aborting'
           CALL Fatal( SolverName, Message)
           STOP
        END IF


     BC => GetBC()
     IF (.NOT.ASSOCIATED( BC ) ) CYCLE

! Find the nodes for which 'Calving Front' = True             
     CalvingFront=.False. 
     CalvingFront = ListGetLogical( BC, 'Calving Front', GotIt )
     IF (CalvingFront) THEN
        NodalZs(1:n) = Zs(ZsPerm(NodeIndexes(1:n)))
        NodalZb(1:n) = Zb(ZbPerm(NodeIndexes(1:n)))
     
       ! Need to access Parent Element to get Material properties
        other_body_id = BoundaryElement % BoundaryInfo % outbody
        IF (other_body_id < 1) THEN ! only one body in calculation
          ParentElement => BoundaryElement % BoundaryInfo % Right
          IF ( .NOT. ASSOCIATED(ParentElement) ) ParentElement => BoundaryElement % BoundaryInfo % Left
        ELSE ! we are dealing with a body-body boundary and asume that the normal is pointing outwards
          ParentElement => BoundaryElement %  BoundaryInfo % Right
          IF (ParentElement % BodyId == other_body_id) ParentElement =>  BoundaryElement % BoundaryInfo % Left
        END IF

        ! Read Density in the Material Section
        Material => GetMaterial(ParentElement)

        NodalDensity=0.0_dp
        NodalDensity(1:n) = ListGetReal( Material, 'SSA Mean Density',n, NodeIndexes,Found)
        IF (.NOT.Found) &
           CALL FATAL(SolverName,'Could not find Material prop.  >SSA Mean Density<')

        ! Read the gravity in the Body Force Section 
        BodyForce => GetBodyForce(ParentElement)
        NodalGravity = 0.0_dp
        IF ( ASSOCIATED( BodyForce ) ) THEN
           IF (STDOFs==1) THEN 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 2', n, NodeIndexes, Found)
           ELSE 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 3', n, NodeIndexes, Found)
           END IF
        END IF

        CALL LocalMatrixBCSSA(  STIFF, FORCE, BoundaryElement, n, ElementNodes,&
               NodalDensity, NodalGravity, NodalZb, NodalZs, rhow, sealevel )
        CALL DefaultUpdateEquations( STIFF, FORCE )
     END IF
  END DO

  CALL DefaultFinishAssembly()

  ! Dirichlet 
  CALL DefaultDirichletBCs()
  
!------------------------------------------------------------------------------
!     Solve the system and check for convergence
!------------------------------------------------------------------------------
      PrevUNorm = UNorm

      UNorm = DefaultSolve()


      RelativeChange = Solver % Variable % NonlinChange
      !IF ( PrevUNorm + UNorm /= 0.0d0 ) THEN
      !   RelativeChange = 2.0d0 * ABS( PrevUNorm - UNorm) / ( PrevUnorm + UNorm)
      !ELSE
      !   RelativeChange = 0.0d0
      !END IF

      WRITE( Message, * ) 'Result Norm   : ', UNorm, PrevUNorm
      CALL Info(SolverName, Message, Level=4 )
      WRITE( Message, * ) 'Relative Change : ', RelativeChange
      CALL Info(SolverName, Message, Level=4 )


      IF ( RelativeChange < NewtonTol .OR. &
                   iter > NewtonIter ) Newton = .TRUE.

!------------------------------------------------------------------------------
      IF ( RelativeChange < NonLinearTol ) EXIT
!------------------------------------------------------------------------------

  END DO ! Loop Non-Linear Iterations

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixUVSSA(  STIFF, FORCE, Element, n, Nodes, gravity, &
           Density, Viscosity, LocalZb, LocalZs, LocalU, &
           LocalV, LocalSliding, cm, MinSRInv, STDOFs , Newton )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), gravity(:), Density(:), &
                     Viscosity(:), LocalZb(:), LocalZs(:), &
                     LocalU(:), LocalV(:) , LocalSliding(:,:)
    INTEGER :: n, cp , STDOFs
    REAL(KIND=dp) :: cm
    TYPE(Element_t), POINTER :: Element
    LOGICAL :: Newton
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), detJ 
    REAL(KIND=dp) :: g, rho, eta, h, dhdx, dhdy , muder
    REAL(KIND=dp) :: gradS(2),Slip(2),  A(2,2), StrainA(2,2),StrainB(2,2), Exx, Eyy, Exy, Ezz, Ee, MinSRInv                            
    REAL(KIND=dp) :: Jac(2*n,2*n),SOL(2*n)
    LOGICAL :: Stat, NewtonLin
    INTEGER :: i, j, t, p, q , dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
!------------------------------------------------------------------------------
    dim = CoordinateSystemDimension()

    STIFF = 0.0d0
    FORCE = 0.0d0
    Jac=0.0d0

! Use Newton Linearisation
    NewtonLin=(Newton.AND.(cm.NE.1.0_dp))


    IP = GaussPoints( Element )
    DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
        IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

! Needed Intergration Point value

       g = ABS(SUM( Gravity(1:n) * Basis(1:n) ))
       rho = SUM( Density(1:n) * Basis(1:n) )
       eta = SUM( Viscosity(1:n) * Basis(1:n) )
       gradS = 0._dp
       gradS(1) = SUM( LocalZs(1:n) * dBasisdx(1:n,1) )
       if (STDOFs == 2) gradS(2) = SUM( LocalZs(1:n) * dBasisdx(1:n,2) )
       h = SUM( (LocalZs(1:n)-LocalZb(1:n)) * Basis(1:n) )
       
       slip = 0.0_dp
       DO i=1,STDOFs
          slip(i) = SUM( LocalSliding(i,1:n) * Basis(1:n) )
       END DO


!------------------------------------------------------------------------------
! In the non-linear case, effective viscosity       
       IF (cm.NE.1.0_dp) THEN
           Exx = SUM(LocalU(1:n)*dBasisdx(1:n,1))
           Eyy = 0.0
           Exy = 0.0
           IF (STDOFs.EQ.2) THEN
              Eyy = SUM(LocalV(1:n)*dBasisdx(1:n,2))
              Ezz = -Exx - Eyy
              Exy = SUM(LocalU(1:n)*dBasisdx(1:n,2))
              Exy = 0.5*(Exy + SUM(LocalV(1:n)*dBasisdx(1:n,1)))
              Ee = 0.5*(Exx**2.0 + Eyy**2.0 + Ezz**2.0) + Exy**2.0
              !Ee = SQRT(Ee)
           ELSE
              !Ee = ABS(Exx)
              Ee = Exx * Exx
           END IF
           muder = eta * 0.5 * (2**cm) * ((cm-1.0)/2.0) *  Ee**((cm-1.0)/2.0 - 1.0)
           IF (sqrt(Ee) < MinSRInv) then
                Ee = MinSRInv*MinSRInv
                muder = 0.0_dp
           Endif
           eta = eta * 0.5 * (2**cm) * Ee**((cm-1.0)/2.0)
       END IF 

       StrainA=0.0_dp
       StrainB=0.0_dp
       If (NewtonLin) then
          StrainA(1,1)=SUM(2.0*dBasisdx(1:n,1)*LocalU(1:n))

          IF (STDOFs.EQ.2) THEN
             StrainB(1,1)=SUM(0.5*dBasisdx(1:n,2)*LocalU(1:n))

             StrainA(1,2)=SUM(dBasisdx(1:n,2)*LocalV(1:n))
             StrainB(1,2)=SUM(0.5*dBasisdx(1:n,1)*LocalV(1:n))

             StrainA(2,1)=SUM(dBasisdx(1:n,1)*LocalU(1:n))
             StrainB(2,1)=SUM(0.5*dBasisdx(1:n,2)*LocalU(1:n))

             StrainA(2,2)=SUM(2.0*dBasisdx(1:n,2)*LocalV(1:n))
             StrainB(2,2)=SUM(0.5*dBasisdx(1:n,1)*LocalV(1:n))

          End if
       Endif

       A = 0.0_dp
       DO p=1,n
         DO q=1,n
         A(1,1) = 2.0*dBasisdx(q,1)*dBasisdx(p,1)  
           IF (STDOFs.EQ.2) THEN
           A(1,1) = A(1,1) + 0.5*dBasisdx(q,2)*dBasisdx(p,2)
           A(1,2) = dBasisdx(q,2)*dBasisdx(p,1) + &
                             0.5*dBasisdx(q,1)*dBasisdx(p,2)
           A(2,1) = dBasisdx(q,1)*dBasisdx(p,2) + &
                             0.5*dBasisdx(q,2)*dBasisdx(p,1)
           A(2,2) = 2.0*dBasisdx(q,2)*dBasisdx(p,2) +&
                             0.5*dBasisdx(q,1)*dBasisdx(p,1)  
         END IF
           A = 2.0 * h * eta * A
           DO i=1,STDOFs
             STIFF((STDOFs)*(p-1)+i,(STDOFs)*(q-1)+i) = STIFF((STDOFs)*(p-1)+i,(STDOFs)*(q-1)+i) +&
                  slip(i) * Basis(q) * Basis(p) * IP % S(t) * detJ
             DO j=1,STDOFs
                STIFF((STDOFs)*(p-1)+i,(STDOFs)*(q-1)+j) = STIFF((STDOFs)*(p-1)+i,(STDOFs)*(q-1)+j) +& 
                      A(i,j) * IP % S(t) * detJ 
             END DO 
           END DO

           If (NewtonLin) then
            ! Maybe a more elegant formulation to get the Jacobian??.......
            IF (STDOFs.EQ.1) THEN
                  Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+1) = Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+1) +&
                        IP % S(t) * detJ * 2.0 * h * StrainA(1,1)*dBasisdx(p,1) * &
                         muder * 2.0 * Exx*dBasisdx(q,1) 

             ELSE IF (STDOFs.EQ.2) THEN
                  Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+1) = Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+1) +&
             IP % S(t) * detJ * 2.0 * h * ((StrainA(1,1)+StrainA(1,2))*dBasisdx(p,1)+(StrainB(1,1)+StrainB(1,2))*dBasisdx(p,2)) * &
             muder *((2.0*Exx+Eyy)*dBasisdx(q,1)+Exy*dBasisdx(q,2)) 

                  Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+2) = Jac((STDOFs)*(p-1)+1,(STDOFs)*(q-1)+2) +&
             IP % S(t) * detJ * 2.0 * h * ((StrainA(1,1)+StrainA(1,2))*dBasisdx(p,1)+(StrainB(1,1)+StrainB(1,2))*dBasisdx(p,2)) * &
             muder *((2.0*Eyy+Exx)*dBasisdx(q,2)+Exy*dBasisdx(q,1)) 

                  Jac((STDOFs)*(p-1)+2,(STDOFs)*(q-1)+1) = Jac((STDOFs)*(p-1)+2,(STDOFs)*(q-1)+1) +&
             IP % S(t) * detJ * 2.0 * h * ((StrainA(2,1)+StrainA(2,2))*dBasisdx(p,2)+(StrainB(2,1)+StrainB(2,2))*dBasisdx(p,1)) * &
             muder *((2.0*Exx+Eyy)*dBasisdx(q,1)+Exy*dBasisdx(q,2)) 

                  Jac((STDOFs)*(p-1)+2,(STDOFs)*(q-1)+2) = Jac((STDOFs)*(p-1)+2,(STDOFs)*(q-1)+2) +&
             IP % S(t) * detJ * 2.0 * h * ((StrainA(2,1)+StrainA(2,2))*dBasisdx(p,2)+(StrainB(2,1)+StrainB(2,2))*dBasisdx(p,1)) * &
             muder *((2.0*Eyy+Exx)*dBasisdx(q,2)+Exy*dBasisdx(q,1)) 
             End if
           Endif

         END DO

         DO i=1,STDOFs
         FORCE((STDOFs)*(p-1)+i) =   FORCE((STDOFs)*(p-1)+i) - &   
            rho*g*h*gradS(i) * IP % s(t) * detJ * Basis(p) 
         END DO
       END DO
    END DO

    If (NewtonLin) then
         SOL(1:STDOFs*n:STDOFs)=LocalU(1:n)
         If (STDOFs.EQ.2) SOL(2:STDOFs*n:STDOFs)=LocalV(1:n)

         STIFF(1:STDOFs*n,1:STDOFs*n) = STIFF(1:STDOFs*n,1:STDOFs*n) + &
                                        Jac(1:STDOFs*n,1:STDOFs*n)
         FORCE(1:STDOFs*n) = FORCE(1:STDOFs*n) + &
                             MATMUL(Jac(1:STDOFs*n,1:STDOFs*n),SOL(1:STDOFs*n))
    Endif
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixUVSSA
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBCSSA(  STIFF, FORCE, Element, n, ENodes, Density, & 
                      Gravity, LocalZb, LocalZs, rhow, sealevel)
!------------------------------------------------------------------------------
    TYPE(Element_t), POINTER :: Element
    TYPE(Nodes_t) ::  ENodes
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:),  density(:), Gravity(:), LocalZb(:),&
                         LocalZs(:),rhow, sealevel
    INTEGER :: n
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3), &
                      DetJ,Normal(3), rhoi, g, alpha, h, h_im,norm
    LOGICAL :: Stat
    INTEGER :: t, i
    TYPE(GaussIntegrationPoints_t) :: IP

!------------------------------------------------------------------------------
    STIFF = 0.0d0
    FORCE = 0.0d0

! The front force is a concentrated nodal force in 1D-SSA and
! a force distributed along a line in 2D-SSA    

! 1D-SSA Case : concentrated force at each nodes
    IF (STDOFs==1) THEN  !1D SSA but should be 2D problem (does elmer work in 1D?)
      DO i = 1, n
         g = ABS( Gravity(i) )
         rhoi = Density(i)
         h = LocalZs(i)-LocalZb(i) 
         h_im=max(0._dp,sealevel-LocalZb(i))
         alpha=0.5 * g * (rhoi * h**2.0 - rhow * h_im**2.0)
         FORCE(i) = FORCE(i) + alpha
      END DO

! 2D-SSA Case : force distributed along the line       
! This will work in DIM=3D only if working with Extruded Mesh and Preserve
! Baseline as been set to True to keep the 1D-BC 
    ELSE IF (STDOFs==2) THEN

          IP = GaussPoints( Element )
          DO t=1,IP % n
             stat = ElementInfo( Element, ENodes, IP % U(t), IP % V(t), &
                 IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )
 
             g = ABS(SUM( Gravity(1:n) * Basis(1:n) ))
             rhoi = SUM( Density(1:n) * Basis(1:n) )
             h = SUM( (LocalZs(1:n)-LocalZb(1:n)) * Basis(1:n))
             h_im = max(0.0_dp , SUM( (sealevel-LocalZb(1:n)) * Basis(1:n)) )
             alpha=0.5 * g * (rhoi * h**2.0 - rhow * h_im**2.0)

! Normal in the (x,y) plane
             Normal = NormalVector( Element, ENodes, IP % U(t), IP % V(t), .TRUE.)
             norm=SQRT(normal(1)**2.0+normal(2)**2.0)
             Normal(1) = Normal(1)/norm
             Normal(2) = Normal(2)/norm

             DO p=1,n
                DO i=1,STDOFs
                   FORCE(STDOFs*(p-1)+i) =   FORCE(STDOFs*(p-1)+i) +&   
                    alpha * Normal(i) * IP % s(t) * detJ * Basis(p) 
                END DO
             END DO
          END DO

    ELSE   

      CALL FATAL('SSASolver-SSABasalSolver','Do not work for STDOFs <> 1 or 2')

    END IF
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBCSSA


!------------------------------------------------------------------------------
END SUBROUTINE SSABasalSolver
!------------------------------------------------------------------------------

! *****************************************************************************
!>   Compute the depth integrated viscosity = sum_zb^zs eta dz
!>     and the depth integrated density = sum_zb^zs rho dz
SUBROUTINE GetMeanValueSolver( Model,Solver,dt,TransientSimulation )
!------------------------------------------------------------------------------
!******************************************************************************
!
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Element_t),POINTER :: CurrentElement, Element, ParentElement, &
                             BoundaryElement
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(ValueList_t), POINTER :: SolverParams, BodyForce, Material
  TYPE(Variable_t), POINTER :: PointerToVariable, IntViscoSol, IntDensSol,&
                                DepthSol  

  LOGICAL :: AllocationsDone = .FALSE., Found

  INTEGER :: i, n, m, t, istat, DIM, COMP, other_body_id   
  INTEGER, POINTER :: Permutation(:), NodeIndexes(:), IntViscoPerm(:),&
                      IntDensPerm(:), DepthPerm(:) 
       
  REAL(KIND=dp), POINTER :: ForceVector(:)
  REAL(KIND=dp), POINTER :: VariableValues(:), IntVisco(:), IntDens(:), Depth(:)
  REAL(KIND=dp) :: Norm, cn, dd 

  REAL(KIND=dp), ALLOCATABLE :: STIFF(:,:), LOAD(:), FORCE(:), &
           NodalVar(:) 

  CHARACTER(LEN=MAX_NAME_LEN) :: SolverName

  SAVE STIFF, LOAD, FORCE, AllocationsDone, DIM, SolverName
  SAVE NodalVar 
!------------------------------------------------------------------------------
  PointerToVariable => Solver % Variable
  Permutation  => PointerToVariable % Perm
  VariableValues => PointerToVariable % Values
  WRITE(SolverName, '(A)') 'SSASolver-IntValue'

  IntViscoSol => VariableGet( Solver % Mesh % Variables, 'Mean Viscosity' )
  IF (ASSOCIATED(IntViscoSol)) THEN
     IntVisco => IntViscoSol % Values
     IntViscoPerm => IntViscoSol % Perm
  ELSE
     CALL FATAL(SolverName,'Could not find variable >Mean Viscosity<')
  END IF
  IntDensSol => VariableGet( Solver % Mesh % Variables, 'Mean Density' )
  IF (ASSOCIATED(IntDensSol)) THEN
     IntDens => IntDensSol % Values
     IntDensPerm => IntDensSol % Perm
  ELSE
     CALL FATAL(SolverName,'Could not find variable >Mean Density<')
  END IF
  DepthSol => VariableGet( Solver % Mesh % Variables, 'Depth' )
  IF (ASSOCIATED(DepthSol)) THEN
     Depth => DepthSol % Values
     DepthPerm => DepthSol % Perm
  ELSE
     CALL FATAL(SolverName,'Could not find variable >Depth<')
  END IF
  !--------------------------------------------------------------
  !Allocate some permanent storage, this is done first time only:
  !--------------------------------------------------------------
  IF ( (.NOT. AllocationsDone) .OR. Solver % Mesh % Changed  ) THEN
     N = Solver % Mesh % MaxElementNodes ! just big enough for elemental arrays
     M = Model % Mesh % NumberOfNodes
     IF (AllocationsDone) DEALLOCATE(FORCE, LOAD, STIFF, NodalVar) 

     ALLOCATE( FORCE(N), LOAD(N), STIFF(N,N), NodalVar(N), &
                          STAT=istat )
     IF ( istat /= 0 ) THEN
        CALL Fatal( SolverName, 'Memory allocation error.' )
     END IF
     AllocationsDone = .TRUE.
     CALL INFO( SolverName, 'Memory allocation done.',Level=1 )
  END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS

! Loop for viscosity and density
DO COMP=1, 2
! No non-linear iteration, no time dependency  
  VariableValues = 0.0d0
  Norm = Solver % Variable % Norm

  !Initialize the system and do the assembly:
  !------------------------------------------
  CALL DefaultInitialize()
  ! bulk assembly
  DO t=1,Solver % NumberOfActiveElements
     Element => GetActiveElement(t)
     IF (ParEnv % myPe .NE. Element % partIndex) CYCLE
     n = GetElementNOFNodes()

     NodeIndexes => Element % NodeIndexes
     Material => GetMaterial(Element)

     IF (COMP==1) THEN
     ! Read the Viscosity eta, 
     ! Same definition as NS Solver in Elmer - n=1/m , A = 1/ (2 eta^n) 
     NodalVar = 0.0D0
     NodalVar(1:n) = ListGetReal( &
         Material, 'Viscosity', n, NodeIndexes, Found )
     ELSE IF (COMP==2) THEN
     NodalVar = 0.0D0
     NodalVar(1:n) = ListGetReal( &
         Material, 'Density', n, NodeIndexes, Found )
     END IF

     CALL LocalMatrix (  STIFF, FORCE, Element, n, NodalVar )
     CALL DefaultUpdateEquations( STIFF, FORCE )
  END DO
  
  ! Neumann conditions 
  DO t=1,Solver % Mesh % NUmberOfBoundaryElements
     BoundaryElement => GetBoundaryElement(t)
     IF ( GetElementFamily() == 1 ) CYCLE
     NodeIndexes => BoundaryElement % NodeIndexes
     IF (ParEnv % myPe .NE. BoundaryElement % partIndex) CYCLE
     n = GetElementNOFNodes()

! Find the Parent element     
     other_body_id = BoundaryElement % BoundaryInfo % outbody
     IF (other_body_id < 1) THEN ! only one body in calculation
         ParentElement => BoundaryElement % BoundaryInfo % Right
         IF ( .NOT. ASSOCIATED(ParentElement) ) ParentElement => BoundaryElement % BoundaryInfo % Left
         ELSE ! we are dealing with a body-body boundary and asume that the normal is pointing outwards
             ParentElement => BoundaryElement % BoundaryInfo % Right
             IF (ParentElement % BodyId == other_body_id) ParentElement => BoundaryElement % BoundaryInfo % Left
         END IF

     Material => GetMaterial(ParentElement)

     IF (COMP==1) THEN
     ! Read the Viscosity eta, 
     ! Same definition as NS Solver in Elmer - n=1/m , A = 1/ (2 eta^n) 
     NodalVar = 0.0D0
     NodalVar(1:n) = ListGetReal( &
         Material, 'Viscosity', n, NodeIndexes, Found )
     ELSE IF (COMP==2) THEN
     NodalVar = 0.0D0
     NodalVar(1:n) = ListGetReal( &
         Material, 'Density', n, NodeIndexes, Found )
     END IF
     CALL LocalMatrixBC(  STIFF, FORCE, BoundaryElement, n, NodalVar)
     CALL DefaultUpdateEquations( STIFF, FORCE )
  END DO

  CALL DefaultFinishAssembly()
  ! Dirichlet 
  IF (COMP==1) THEN
     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          'Mean Viscosity', 1,1, Permutation )
  ELSE
     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          'Mean Density', 1,1, Permutation )
  END IF
  Norm = DefaultSolve()

  ! Save the solution on the right variable
  IF (COMP==1) THEN
     DO i = 1, Model % Mesh % NumberOfNodes
        IF (IntViscoPerm(i)>0) THEN
            IntVisco(IntViscoPerm(i)) = VariableValues(Permutation(i)) 
            IF (Depth(DepthPerm(i))>0.0_dp) IntVisco(IntViscoPerm(i)) = &
                 IntVisco(IntViscoPerm(i)) / Depth(DepthPerm(i))
        END IF
     END DO
  ELSE IF (COMP==2) THEN
     DO i = 1, Model % Mesh % NumberOfNodes
        IF (IntDensPerm(i)>0) THEN
            IntDens(IntDensPerm(i)) = VariableValues(Permutation(i)) 
            IF (Depth(DepthPerm(i))>0.0_dp) IntDens(IntDensPerm(i)) = &
                IntDens(IntDensPerm(i)) / Depth(DepthPerm(i))
                                                 
                                                 
        END IF
     END DO
  END IF
  
END DO !COMP


CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrix(  STIFF, FORCE, Element, n, var)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), var(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), detJ, grad
    LOGICAL :: Stat
    INTEGER :: t, p,q ,dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    dim = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
          IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )
         
        grad  = SUM( var(1:n) * dBasisdx(1:n,dim) )
        FORCE(1:n) = FORCE(1:n) + grad * IP % s(t) * DetJ  * Basis(1:n)
       
       DO p=1,n
         DO q=1,n
           STIFF(p,q) = STIFF(p,q) + IP % S(t) * detJ * dBasisdx(q,dim)*dBasisdx(p,dim)
         END DO
       END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrix
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBC(  STIFF, FORCE, Element, n, var ) 
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), var(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3), &
                      DetJ,Normal(3), eta, grad 
    LOGICAL :: Stat
    INTEGER :: t, dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    dim = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
       IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

       grad  = SUM( var(1:n) * Basis(1:n) )

      Normal = NormalVector( Element, Nodes, IP % U(t), IP % V(t), .TRUE.)
      FORCE(1:n) = FORCE(1:n) - grad * IP % s(t) * DetJ * Normal(dim) * Basis(1:n)
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBC
!------------------------------------------------------------------------------
END SUBROUTINE GetMeanValueSolver
!------------------------------------------------------------------------------


! *****************************************************************************
SUBROUTINE SSASolver( Model,Solver,dt,TransientSimulation )
!DEC$ATTRIBUTES DLLEXPORT :: SSASolver
!------------------------------------------------------------------------------
!******************************************************************************
!
!  Export vertically the SSABasal Velocity (given as a Dirichlet Boundary condition) 
!  Compute also the vertical velocity and the pressure
!
!  ARGUMENTS:
!
!  TYPE(Model_t) :: Model,  
!     INPUT: All model information (mesh, materials, BCs, etc...)
!
!  TYPE(Solver_t) :: Solver
!     INPUT: Linear & nonlinear equation solver options
!
!  REAL(KIND=dp) :: dt,
!     INPUT: Timestep size for time dependent simulations
!
!  LOGICAL :: TransientSimulation
!     INPUT: Steady state or transient simulation
!
!******************************************************************************
  USE DefUtils

  IMPLICIT NONE
!------------------------------------------------------------------------------
  TYPE(Solver_t) :: Solver
  TYPE(Model_t) :: Model

  REAL(KIND=dp) :: dt
  LOGICAL :: TransientSimulation
!------------------------------------------------------------------------------
! Local variables
!------------------------------------------------------------------------------
  TYPE(Element_t),POINTER :: CurrentElement, Element
  TYPE(Matrix_t),POINTER  :: StiffMatrix
  TYPE(ValueList_t), POINTER :: SolverParams, BodyForce, Material
  TYPE(Variable_t), POINTER :: PointerToVariable, Grad1Sol, Grad2Sol, &
                               DepthSol, VeloSol

  LOGICAL :: AllocationsDone = .FALSE., Found

  INTEGER :: i, n, m, t, istat, DIM, p, Indexes(128), COMP 
  INTEGER, POINTER :: Permutation(:), VeloPerm(:), &
       DepthPerm(:), GradSurface1Perm(:), GradSurface2Perm(:), &
       NodeIndexes(:)

  REAL(KIND=dp), POINTER :: ForceVector(:)
  REAL(KIND=dp), POINTER :: VariableValues(:), Depth(:), GradSurface1(:), &
                            GradSurface2(:), Velocity(:), PrevVelo(:,:)
  REAL(KIND=dp) :: Norm, cn, dd 

  REAL(KIND=dp), ALLOCATABLE :: STIFF(:,:), LOAD(:), FORCE(:), &
           NodalGravity(:), NodalDensity(:), &
           NodalDepth(:), NodalSurfGrad1(:), NodalSurfGrad2(:), &
           NodalU(:), NodalV(:)

  CHARACTER(LEN=MAX_NAME_LEN) :: SolverName
       

  SAVE STIFF, LOAD, FORCE, AllocationsDone, DIM, SolverName
  SAVE NodalGravity, NodalDensity, &
           NodalDepth, NodalSurfGrad1, NodalSurfGrad2, &
           NodalU, NodalV
!------------------------------------------------------------------------------
  PointerToVariable => Solver % Variable
  Permutation  => PointerToVariable % Perm
  VariableValues => PointerToVariable % Values
  WRITE(SolverName, '(A)') 'SSASolver'

!------------------------------------------------------------------------------
!    Get variables needed for solution
!------------------------------------------------------------------------------
        DIM = CoordinateSystemDimension()

        VeloSol => VariableGet( Solver % Mesh % Variables, 'SSAFlow' )
        IF (ASSOCIATED(veloSol)) THEN
           Velocity => VeloSol % Values
           VeloPerm => VeloSol % Perm
           PrevVelo => veloSol % PrevValues
        ELSE
           CALL FATAL(SolverName,'Could not find variable >SSAFlow<')
        END IF
        DepthSol => VariableGet( Solver % Mesh % Variables, 'Depth' )
        IF (ASSOCIATED(DepthSol)) THEN
           Depth => DepthSol % Values
           DepthPerm => DepthSol % Perm
        ELSE
           CALL FATAL(SolverName,'Could not find variable >Depth<')
        END IF
        Grad1Sol => VariableGet( Solver % Mesh % Variables, 'FreeSurfGrad1')
        IF (ASSOCIATED(Grad1Sol)) THEN
           GradSurface1 => Grad1Sol % Values
           GradSurface1Perm => Grad1Sol % Perm
        ELSE
           CALL FATAL(SolverName,'Could not find variable >FreeSurfGrad1<')
        END IF
        IF (dim > 2) THEN
           Grad2Sol => VariableGet( Solver % Mesh % Variables, 'FreeSurfGrad2')
           IF (ASSOCIATED(Grad2Sol)) THEN
              GradSurface2 => Grad2Sol % Values
              GradSurface2Perm => Grad2Sol % Perm
           ELSE
              CALL FATAL(SolverName,'Could not find variable >FreeSurfGrad2<')
           END IF
        END IF

  !--------------------------------------------------------------
  !Allocate some permanent storage, this is done first time only:
  !--------------------------------------------------------------
  IF ( (.NOT. AllocationsDone) .OR. Solver % Mesh % Changed  ) THEN
     N = Solver % Mesh % MaxElementNodes ! just big enough for elemental arrays
     M = Model % Mesh % NumberOfNodes
     IF (AllocationsDone) DEALLOCATE(FORCE, LOAD, STIFF, NodalGravity, &
                       NodalDensity, NodalDepth, &
                       NodalSurfGrad1, NodalSurfGrad2, NodalU, NodalV )

     ALLOCATE( FORCE(N), LOAD(N), STIFF(N,N), &
          NodalGravity(N), NodalDensity(N), &
          NodalDepth(N), NodalSurfGrad1(N), NodalSurfGrad2(N), &
          NodalU(N), NodalV(N), STAT=istat )
     IF ( istat /= 0 ) THEN
        CALL Fatal( SolverName, 'Memory allocation error.' )
     END IF


     AllocationsDone = .TRUE.
     CALL INFO( SolverName, 'Memory allocation done.',Level=1 )
  END IF

     StiffMatrix => Solver % Matrix
     ForceVector => StiffMatrix % RHS

  ! Loop over the velocity components and pressure 
  ! If DIM = 2 u, w, p
  ! If DIM = 3 u, v, w, p
  !-----------------------------------------------
  DO  COMP = 1, DIM+1

! No non-linear iteration, no time dependency  
  VariableValues = 0.0d0
  Norm = Solver % Variable % Norm


  !Initialize the system and do the assembly:
  !------------------------------------------
  CALL DefaultInitialize()
  ! bulk assembly
  DO t=1,Solver % NumberOfActiveElements
     Element => GetActiveElement(t)
     IF (ParEnv % myPe .NE. Element % partIndex) CYCLE
     n = GetElementNOFNodes()

     NodeIndexes => Element % NodeIndexes

     ! Read the gravity in the Body Force Section 
     BodyForce => GetBodyForce()
     NodalGravity = 0.0_dp
     IF ( ASSOCIATED( BodyForce ) ) THEN
           IF (DIM==2) THEN 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 2', n, NodeIndexes, Found)
           ELSE 
           NodalGravity(1:n) = ListGetReal( &
                   BodyForce, 'Flow BodyForce 3', n, NodeIndexes, Found)
           END IF
     END IF
     
     ! Read the Viscosity eta, density, and exponent m in Material Section
     ! Same definition as NS Solver in Elmer - n=1/m , A = 1/ (2 eta^n) 
     Material => GetMaterial()

     NodalDensity = 0.0D0
     NodalDensity(1:n) = ListGetReal( &
         Material, 'Density', n, NodeIndexes, Found )

     ! Get the Nodal value of Depth, FreeSurfGrad1 and FreeSurfGrad2
     NodalDepth(1:n) = Depth(DepthPerm(NodeIndexes(1:n)))
     NodalSurfGrad1(1:n) = GradSurface1(GradSurface1Perm(NodeIndexes(1:n)))
     NodalSurfGrad2 = 0.0D0
     IF (DIM==3) NodalSurfGrad2(1:n) = GradSurface2(GradSurface2Perm(NodeIndexes(1:n)))

     IF (COMP==1) THEN     ! u
        CALL LocalMatrixUV (  STIFF, FORCE, Element, n ) 

     ELSE IF (COMP==DIM) THEN  ! w
        NodalU(1:n) = Velocity((DIM+1)*(VeloPerm(NodeIndexes(1:n))-1)+1)
        NodalV = 0.0D0
        IF (DIM==3) NodalV(1:n) = Velocity((DIM+1)*(VeloPerm(NodeIndexes(1:n))-1)+2)
        CALL LocalMatrixW (  STIFF, FORCE, Element, n, NodalU, NodalV ) 

     ELSE IF (COMP==DIM+1) THEN ! p
        CALL LocalMatrixP (  STIFF, FORCE, Element, n )

     ELSE               ! v if dim=3
        CALL LocalMatrixUV (  STIFF, FORCE, Element, n )

     END IF

     CALL DefaultUpdateEquations( STIFF, FORCE )
  END DO
  
  ! Neumann conditions only for w and p
  IF (COMP .GE. DIM) THEN
  DO t=1,Solver % Mesh % NUmberOfBoundaryElements
     Element => GetBoundaryElement(t)
     IF ( GetElementFamily() == 1 ) CYCLE
     NodeIndexes => Element % NodeIndexes
     IF (ParEnv % myPe .NE. Element % partIndex) CYCLE
     n = GetElementNOFNodes()
     STIFF = 0.0D00
     FORCE = 0.0D00

     IF (COMP==DIM) THEN
     ! only for the surface nodes
        dd = SUM(ABS(Depth(Depthperm(NodeIndexes(1:n)))))
        IF (dd < 1.0e-6) THEN
           NodalU(1:n) = Velocity((DIM+1)*(VeloPerm(NodeIndexes(1:n))-1)+1)
           NodalV = 0.0D0
           IF (DIM==3) NodalV(1:n) = Velocity((DIM+1)*(VeloPerm(NodeIndexes(1:n))-1)+2)
           CALL LocalMatrixBCW (  STIFF, FORCE, Element, n, NodalU, NodalV ) 
        END IF
     ELSE IF (COMP==DIM+1) THEN
            CALL LocalMatrixBCP(  STIFF, FORCE, Element, n, NodalDensity, &
                    NodalGravity )
     END IF
     CALL DefaultUpdateEquations( STIFF, FORCE )
  END DO
  END IF

  CALL DefaultFinishAssembly()

  ! Dirichlet 
     CALL SetDirichletBoundaries( Model, StiffMatrix, ForceVector, &
          ComponentName('SSAFlow',COMP), 1,1, Permutation )
  
  !Solve the system
  Norm = DefaultSolve()

  ! Save the solution on the right variable
         DO i = 1, Model % Mesh % NumberOfNodes
           IF (VeloPerm(i)>0) THEN
           Velocity ((DIM+1)*(VeloPerm(i)-1) + COMP) = VariableValues(Permutation(i)) 
           END IF
         END DO 

  END DO ! Loop p

CONTAINS

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixUV(  STIFF, FORCE, Element, n ) 
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), detJ 
    LOGICAL :: Stat
    INTEGER :: t, p, q , dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    dim = CoordinateSystemDimension()


    IP = GaussPoints( Element )
    DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
        IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

       DO p=1,n
         DO q=1,n
           STIFF(p,q) = STIFF(p,q) + IP % S(t) * detJ * dBasisdx(q,dim)*dBasisdx(p,dim)
         END DO
       END DO

    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixUV
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixW(  STIFF, FORCE, Element, n, VeloU, VeloV)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), VeloU(:), VeloV(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), detJ, &
                     dU2dxz, dV2dyz
    LOGICAL :: Stat
    INTEGER :: t, p,q , DIM
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    DIM = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
        IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .TRUE. )

       DO p=1,n
         DO q=1,n
           STIFF(p,q) = STIFF(p,q) + IP % S(t) * detJ * dBasisdx(q,dim)*dBasisdx(p,dim)
         END DO
       END DO

       dU2dxz = SUM(VeloU(1:n)*ddBasisddx(1:n,1,dim))
       dV2dyz = 0.0d0
       IF (DIM==3) dV2dyz = SUM(VeloV(1:n)*ddBasisddx(1:n,2,3))
       

       FORCE(1:n) = FORCE(1:n) + (dU2dxz + dV2dyz) * IP % s(t) * detJ * Basis(1:n) 

    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixW

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixP(  STIFF, FORCE, Element, n)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n), dBasisdx(n,3), ddBasisddx(n,3,3), detJ
    LOGICAL :: Stat
    INTEGER :: t, p,q ,dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    dim = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
       stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
        IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

       DO p=1,n
         DO q=1,n
           STIFF(p,q) = STIFF(p,q) + IP % S(t) * detJ * dBasisdx(q,dim)*dBasisdx(p,dim)
         END DO
       END DO
    END DO

!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixP
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBCW(  STIFF, FORCE, Element, n, VeloU, VeloV )
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), veloU(:), veloV(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3), &
                      DetJ, Normal(3), grad, dUdx, dVdy  
    LOGICAL :: Stat
    INTEGER :: t, DIM
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    DIM = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
       IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

       dUdx = SUM( VeloU(1:n) * dBasisdx(1:n,1) )
       dVdy = 0.0e0
       IF (DIM==3) dVdy = SUM( VeloV(1:n) * dBasisdx(1:n,2) )

       grad = - (dUdx + dVdy) 

      Normal = NormalVector( Element, Nodes, IP % U(t), IP % V(t), .TRUE.)
      FORCE(1:n) = FORCE(1:n) + grad * IP % s(t) * DetJ * Normal(dim) * Basis(1:n)
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBCW
!------------------------------------------------------------------------------

!------------------------------------------------------------------------------
  SUBROUTINE LocalMatrixBCP(  STIFF, FORCE, Element, n, Density, & 
                      Gravity)
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: STIFF(:,:), FORCE(:), density(:), Gravity(:)
    INTEGER :: n
    TYPE(Element_t), POINTER :: Element
!------------------------------------------------------------------------------
    REAL(KIND=dp) :: Basis(n),dBasisdx(n,3),ddBasisddx(n,3,3), &
                      DetJ,Normal(3), rho, g, grad
    LOGICAL :: Stat
    INTEGER :: t, dim
    TYPE(GaussIntegrationPoints_t) :: IP

    TYPE(Nodes_t) :: Nodes
    SAVE Nodes
!------------------------------------------------------------------------------
    CALL GetElementNodes( Nodes )
    STIFF = 0.0d0
    FORCE = 0.0d0

    dim = CoordinateSystemDimension()

    IP = GaussPoints( Element )
    DO t=1,IP % n
      stat = ElementInfo( Element, Nodes, IP % U(t), IP % V(t), &
       IP % W(t),  detJ, Basis, dBasisdx, ddBasisddx, .FALSE. )

       g = ABS(SUM( Gravity(1:n) * Basis(1:n) ))
       rho = SUM( Density(1:n) * Basis(1:n) )

       grad = - rho * g 

      Normal = NormalVector( Element, Nodes, IP % U(t), IP % V(t), .TRUE.)
      FORCE(1:n) = FORCE(1:n) + grad * IP % s(t) * DetJ * Normal(dim) * Basis(1:n)
    END DO
!------------------------------------------------------------------------------
  END SUBROUTINE LocalMatrixBCP
!------------------------------------------------------------------------------
END SUBROUTINE SSASolver
!------------------------------------------------------------------------------


