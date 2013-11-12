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
! *  Authors: 
! *  Email:   
! *  Web:     http://elmerice.elmerfem.org
! *
! *  Original Date: 
! * 
! *****************************************************************************
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!  Interpolate data given on a regular 2D regular grid in an ASCII file (x y Value)
!    in the mesh nodes using bilinear interpolation
!    The data are ordered such that   
!    x1 y1 val11
!    x2 y1 val21
!    ...
!    xn y1 valn1
!    x1 y2 val12
!    ...
!    xn yn valnn 
!    
!    The grid is described by giving:
!    (x0, y0) the left-bottom corner coordinate
!    (lx, ly) the x and y lengths of the covered domain
!    (Nx, Ny) the number of cells in x and y directions 
!    No data are given by -9999
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
SUBROUTINE Grid2DInterpolator( Model,Solver,dt,TransientSimulation )

   USE DefUtils

   IMPLICIT NONE
   TYPE(Solver_t), TARGET :: Solver
   TYPE(Model_t) :: Model
   REAL(KIND=dp) :: dt
   LOGICAL :: TransientSimulation

   TYPE(ValueList_t), POINTER :: Params
   TYPE(Variable_t), POINTER :: Var
   REAL(KIND=dp), POINTER :: Values(:)
   INTEGER, POINTER :: Perm(:)

   REAL(KIND=DP) :: Rmin, Rmax
   REAL(KIND=DP) :: x, y, z, x0, y0, lx, ly, dx, dy
   REAL(KIND=DP), ALLOCATABLE :: xb(:), yb(:), zb(:)

   INTEGER,parameter :: io=20
   INTEGER :: ok, Nx, Ny, Nb, OutNode
   INTEGER :: i, j, k, kmin, NoVar

   CHARACTER(LEN=MAX_NAME_LEN) :: VariableName, DataF
   CHARACTER(LEN=MAX_NAME_LEN) :: Name, FName, ParaName
   CHARACTER(LEN=MAX_NAME_LEN), PARAMETER :: SolverName='Grid2DInterpolator'

   LOGICAL :: GotVar, Found

   Params => GetSolverParams()

   ! Read variable to initialize and Data
   NoVar=0
   GotVar=.True.

   DO WHILE(GotVar)
      NoVar = NoVar + 1
      WRITE (Name,'(A,I0)') 'Variable ',NoVar

      VariableName = ListGetString( Params, TRIM(Name), GotVar )
      IF (.NOT.GotVar) EXIT

      Var => VariableGet(Model %  Mesh % Variables, VariableName )
      IF(.NOT.ASSOCIATED(Var)) THEN
         WRITE(message,'(A,A,A)') &
                        'Variable <',Trim(VariableName),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      ELSE
         Values => Var % Values
         Perm => Var % Perm
      END IF

      WRITE (FName,'(A,I0,A)') 'Variable ',NoVar,' Data File'
      DataF = ListGetString( Params, TRIM(FName), Found )

      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF

      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' x0'
      x0 = ListGetConstReal( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF

      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' y0'
      y0 = ListGetConstReal( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF
            
      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' lx'
      lx = ListGetConstReal( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF
            
      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' ly'
      ly = ListGetConstReal( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF

      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' Nx'
      Nx = ListGetInteger( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF

      WRITE (ParaName,'(A,I0,A)') 'Variable ',NoVar,' Ny'
      Ny = ListGetInteger( Params, TRIM(ParaName), Found )
      IF (.NOT.Found) then
         WRITE(message,'(A,A,A)')'Keyword <',Trim(Fname),'> not found'
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF

      OPEN(unit = io, file = TRIM(DataF), status = 'old',iostat = ok)

      IF (ok /= 0) THEN
         WRITE(message,'(A,A)') 'Unable to open file ',TRIM(DataF)
         CALL FATAL(Trim(SolverName),Trim(message))
      END IF
            
      Nb = Nx*Ny 
          
      ALLOCATE(xb(Nb), yb(Nb), zb(Nb))

      ! read datas
      DO i = 1, Nb 
         READ(io,*,iostat = ok) xb(i), yb(i), zb(i)
      END DO
      CLOSE(io)

      ! Make some verifications on the DEM structure
      dx = lx / (Nx-1.0)
      dy = ly / (Ny-1.0)
      k = 0 
      DO j = 1, Ny
         y = y0 + dy*(j-1)
         DO i = 1, Nx 
             k = k + 1
             x = x0 + dx*(i-1)
             IF ((ABS(x-xb(k))>1.0e-6*dx).OR.(ABS(y-yb(k))>1.0e-6*dy)) THEN
                WRITE(Message,'(A,A)')'Structure of the DEM is not conforming to what is given in the sif for ',TRIM(FName) 
                CALL INFO(SolverName, Message, Level=1)
                WRITE(Message,'(A,i4,A,e14.8,2x,e14.8,A,e14.8,2x,e14.8,A)') &
                   'Found that point ',k,' coordinate is (',xb(k),yb(k),'), whereas it should be (',x,y,')' 
                CALL FATAL(SolverName, Message) 
             END IF
         END DO
      END DO

      OutNode = 0
      Rmax = 0.0
      DO i=1,Model % Mesh % NumberOfNodes
         x = Model % Mesh % Nodes % x(i)
         y = Model % Mesh % Nodes % y(i)
         Rmin = 0.0
         CALL InterpolateDEM(x,y,xb,yb,zb,Nx,Ny,x0,y0,lx,ly,Rmin,z)
         Values(Perm(i)) = z
         IF (Rmin > 0.0) THEN
            OutNode = OutNode + 1
            IF (Rmin > Rmax) Rmax = Rmin
         END IF
      END DO
          
      ! Give information on the number of Nodes which are outside of the
      ! DEM domain
      IF (OutNode > 0) THEN
         WRITE( Message, '(I0,A,A)' )OutNode,' nodes where found outside of &
                 the DEM domain in ',TRIM(DataF)
         CALL Info( TRIM(SolverName), Message, Level=3 )
         WRITE( Message, '(A,e14.8)' )'The farthest DEM point used to evaluate & 
                 the nodal value was: ', Rmax
         CALL Info( TRIM(SolverName), Message, Level=3 )
      END IF
            
      DEALLOCATE(xb, yb, zb)
   END DO

   CALL INFO(Trim(SolverName), '----------ALL DONE----------',Level=5)

END SUBROUTINE Grid2DInterpolator


!!!!!!!!!!!!!!!!!!!
! Subroutine InterpolateDEM
!!------------------------------------------------------------------------------!!
SUBROUTINE InterpolateDEM (x, y, xb, yb, zb, Nbx, Nby, xb0, yb0, lbx, lby, Rmin, zbed)
   USE DefUtils
   IMPLICIT NONE
   INTEGER :: imin, Npt, t
   INTEGER :: NMAX, i, j, Nb, Nbx, Nby, ib, ix, iy
   REAL(KIND=dp) :: x, y, zbed, xb0, yb0, x1, x2, y1, y2, zi(2,2) 
   REAL(KIND=dp) :: R, Rmin, lbx, lby, dbx, dby
   REAL(KIND=dp) :: xb(Nbx*Nby), yb(Nbx*Nby), zb(Nbx*Nby)       
   REAL(KIND=dp), PARAMETER :: noData = -9999.0, noDataTol = 0.001

   ! Find zbed for that point from the Bedrock MNT 
   dbx = lbx / (Nbx-1.0)
   dby = lby / (Nby-1.0)
   Nb = Nbx*Nby

   ix = INT((x-xb0)/dbx)+1
   iy = INT((y-yb0)/dbx)+1
   ib = Nbx * (iy - 1) + ix
   
   ! if we are already at the end of the domain then collapse the 2 by 2 interpolation 
   ! square to just 2 points at the end of the domain (else we get interpolation involving 
   ! points at the beginning of the domain).  This comment refers to the x direction.
   IF (MOD(ib,Nbx) .eq. 0.0) THEN
      zi(2,1) = -9999.0
      zi(2,2) = -9999.0
   ELSE
      zi(2,1) = zb(ib+1)
      zi(2,2) = zb(ib + Nbx + 1)
   END IF

   x1 = xb(ib)
   x2 = xb(ib+1)
   y1 = yb(ib)
   y2 = yb(ib + Nbx)
        
   zi(1,1) = zb(ib)
   zi(1,2) = zb(ib + Nbx)

!   IF ((zi(1,1)<-9990.0).OR.(zi(1,2)<-9990.0).OR.(zi(2,1)<-9990.0).OR.(zi(2,2)<-9990.0)) THEN
!      IF ((zi(1,1)<-9990.0).AND.(zi(1,2)<-9990.0).AND.(zi(2,1)<-9990.0).AND.(zi(2,2)<-9990.0)) THEN
   IF ( (isNoData(zi(1,1))).OR. &
        (isNoData(zi(1,2))).OR. &
        (isNoData(zi(2,1))).OR. &
        (isNoData(zi(2,2))) ) THEN
      IF ( (isNoData(zi(1,1))).AND. &
           (isNoData(zi(1,2))).AND. &
           (isNoData(zi(2,1))).AND. &
           (isNoData(zi(2,2))) ) THEN

         ! Find the nearest point avalable if all neighbouring points have noData
         Rmin = 9999.0
         DO i=1, Nb
            IF (zb(i)>-9990.0) THEN
               R = SQRT((x-xb(i))**2.0+(y-yb(i))**2.0)
               IF (R<Rmin) THEN
                  Rmin = R
                  imin = i
               END IF
            END IF
         END DO
         zbed = zb(imin)
                        
      ELSE
         ! Mean value over the avalable data if only some points have noData
         zbed = 0.0
         Npt = 0
         DO i=1, 2
            DO J=1, 2
               IF (.NOT. isNoData(zi(i,j))) THEN 
                  zbed = zbed + zi(i,j)
                  Npt = Npt + 1
               END IF   
            END DO
         END DO
         zbed = zbed / Npt
      END IF
   ELSE
      ! linear interpolation is only carried out if all 4 neighbouring points have data.
      zbed = (zi(1,1)*(x2-x)*(y2-y)+zi(2,1)*(x-x1)*(y2-y)+zi(1,2)*(x2-x)*(y-y1)+zi(2,2)*(x-x1)*(y-y1))/(dbx*dby)      
   END IF


 CONTAINS

   LOGICAL FUNCTION isNoData(val)

     IMPLICIT NONE
     REAL(KIND=dp),INTENT(IN) :: val

     IF ((val .GT. noData-noDataTol) .AND. (val .LT. noData+noDataTol)) THEN
        isNoData = .TRUE.
     ELSE
        isNoData = .FALSE.
     END IF

   RETURN 

 END FUNCTION isNoData

END SUBROUTINE InterpolateDEM

