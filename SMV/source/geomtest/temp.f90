! VVVVV placeholder modules - will not be moved to FDS VVVVV

! ------------ MODULE PRECISION_PARAMETERS ---------------------------------

MODULE PRECISION_PARAMETERS
 
! Set important parameters having to do with variable precision and array allocations
 
IMPLICIT NONE
 
! Precision of "Four Byte" and "Eight Byte" reals

INTEGER, PARAMETER :: FB = SELECTED_REAL_KIND(6)
INTEGER, PARAMETER :: EB = SELECTED_REAL_KIND(12)
REAL(EB) ::TWO_EPSILON_EB=2.0_EB*EPSILON(1.0_EB)
END MODULE PRECISION_PARAMETERS

! ------------ MODULE COMP_FUNCTIONS ---------------------------------

MODULE COMP_FUNCTIONS
IMPLICIT NONE

CONTAINS

! ------------ SUBROUTINE SHUTDOWN ---------------------------------

SUBROUTINE SHUTDOWN(MESSAGE)  
CHARACTER(*), INTENT(IN) :: MESSAGE

WRITE(6,'(/A)') TRIM(MESSAGE)

STOP

END SUBROUTINE SHUTDOWN

! ------------ SUBROUTINE CHECKREAD ---------------------------------

SUBROUTINE CHECKREAD(NAME,LU,IOS)

! Look for the namelist variable NAME and then stop at that line.

INTEGER :: II
INTEGER, INTENT(OUT) :: IOS
INTEGER, INTENT(IN) :: LU
CHARACTER(4), INTENT(IN) :: NAME
CHARACTER(80) TEXT
IOS = 1

READLOOP: DO
   READ(LU,'(A)',END=10) TEXT
   TLOOP: DO II=1,72
      IF (TEXT(II:II)/='&' .AND. TEXT(II:II)/=' ') EXIT TLOOP
      IF (TEXT(II:II)=='&') THEN
         IF (TEXT(II+1:II+4)==NAME) THEN
            BACKSPACE(LU)
            IOS = 0
            EXIT READLOOP
         ELSE
            CYCLE READLOOP
         ENDIF
      ENDIF
   ENDDO TLOOP
ENDDO READLOOP
 
10 RETURN
END SUBROUTINE CHECKREAD

END MODULE COMP_FUNCTIONS

! ------------ SUBROUTINE MEMORY_FUNCTIONS ---------------------------------

MODULE MEMORY_FUNCTIONS

USE COMP_FUNCTIONS, ONLY: SHUTDOWN
IMPLICIT NONE

CONTAINS

! ------------ SUBROUTINE ChkMemErr ---------------------------------

SUBROUTINE ChkMemErr(CodeSect,VarName,IZERO)
 
! Memory checking routine
 
CHARACTER(*), INTENT(IN) :: CodeSect, VarName
INTEGER IZERO
CHARACTER(100) MESSAGE
 
IF (IZERO==0) RETURN
 
WRITE(MESSAGE,'(4A)') 'ERROR: Memory allocation failed for ', TRIM(VarName),' in the routine ',TRIM(CodeSect)
CALL SHUTDOWN(MESSAGE)

END SUBROUTINE ChkMemErr
END MODULE MEMORY_FUNCTIONS

! ^^^^ placeholder routines and modules ^^^^^^^

! ------------ MODULE TYPES ---------------------------------

MODULE TYPES
USE PRECISION_PARAMETERS

! VVVVVVVVVVVVV move to FDS in TYPES module VVVVVVVVVVVVVVVVVVVVVVVV

TYPE GEOMETRY_TYPE ! this TYPE definition will be moved to FDS
   CHARACTER(30) :: ID='geom', SURF_ID='null'
   LOGICAL :: COMPONENT_ONLY, HAS_SURF=.FALSE., IS_DYNAMIC=.TRUE.
   INTEGER :: N_VERTS_BASE, N_FACES_BASE, N_VERTS, N_FACES, NSUB_GEOMS
   INTEGER, ALLOCATABLE, DIMENSION(:) :: FACES, SUB_GEOMS, SURFS
   REAL(EB) :: AZIM_BASE, ELEV_BASE, XYZ0(3), SCALE_BASE(3), XYZ_BASE(3)
   REAL(EB) :: AZIM, ELEV, SCALE(3), XYZ(3)
   REAL(EB) :: AZIM_DOT, ELEV_DOT, SCALE_DOT(3), XYZ_DOT(3)
   REAL(EB), ALLOCATABLE, DIMENSION(:) :: VERTS_BASE, VERTS, DAZIM, DELEV
   REAL(EB), ALLOCATABLE, DIMENSION(:,:) :: DSCALE, DXYZ0, DXYZ
END TYPE GEOMETRY_TYPE

INTEGER :: N_GEOMETRY=0
TYPE(GEOMETRY_TYPE), ALLOCATABLE, TARGET, DIMENSION(:) :: GEOMETRY
LOGICAL :: IS_GEOMETRY_DYNAMIC

! ^^^^^^^^^^^^^ move to FDS ^^^^^^^^^^^^^^^^^^^^^^^

TYPE MESH_TYPE
   INTEGER :: IBAR, JBAR, KBAR
   REAL(EB) :: XB(6)
END TYPE MESH_TYPE

TYPE SURF_TYPE
   CHARACTER(60) :: ID
   INTEGER :: RGB(3)
END TYPE SURF_TYPE

INTEGER :: N_SURF=0
TYPE(SURF_TYPE), ALLOCATABLE, TARGET, DIMENSION(:) :: SURFACE

TYPE (MESH_TYPE), SAVE, DIMENSION(:), ALLOCATABLE, TARGET :: MESHES

END MODULE TYPES

! ------------ MODULE GLOBAL_CONSTANTS ---------------------------------

MODULE GLOBAL_CONSTANTS
USE PRECISION_PARAMETERS
IMPLICIT NONE

INTEGER :: LU_INPUT=5, LU_GEOM(1)=15, LU_SMV=4
CHARACTER(40) :: CHID
CHARACTER(250)                             :: FN_INPUT='null'
CHARACTER(80) :: FN_SMV,FN_GEOM(1)
REAL(EB) :: T_BEGIN,T_END
INTEGER :: NSTEPS=1000
END MODULE GLOBAL_CONSTANTS

! ------------ MODULE READ_INPUT ---------------------------------

MODULE READ_INPUT

USE PRECISION_PARAMETERS
USE GLOBAL_CONSTANTS
USE COMP_FUNCTIONS, ONLY: CHECKREAD,SHUTDOWN
USE MEMORY_FUNCTIONS, ONLY: ChkMemErr
USE TYPES
IMPLICIT NONE
INTEGER :: NMESHES

PRIVATE
PUBLIC :: READ_HEAD,READ_MESH,READ_SURF,READ_TIME,GET_SURF_INDEX,N_SURF,NMESHES

CHARACTER(30) :: ID

CONTAINS

! ------------ SUBROUTINE READ_HEAD ---------------------------------

SUBROUTINE READ_HEAD
INTEGER :: NAMELENGTH
INTEGER :: IOS, I

NAMELIST /HEAD/ CHID

CHID    = 'null'

REWIND(LU_INPUT)
HEAD_LOOP: DO
   CALL CHECKREAD('HEAD',LU_INPUT,IOS)
   IF (IOS==1) EXIT HEAD_LOOP
   READ(LU_INPUT,HEAD,END=13,ERR=14,IOSTAT=IOS)
   14 IF (IOS>0) CALL SHUTDOWN('ERROR: Problem with HEAD line')
ENDDO HEAD_LOOP
13 REWIND(LU_INPUT)

CLOOP: DO I=1,39
   IF (CHID(I:I)=='.') CALL SHUTDOWN('ERROR: No periods allowed in CHID')
   IF (CHID(I:I)==' ') EXIT CLOOP
ENDDO CLOOP

IF (TRIM(CHID)=='null') THEN
   NAMELENGTH = LEN_TRIM(FN_INPUT)
   ROOTNAME: DO I=NAMELENGTH,2,-1
      IF (FN_INPUT(I:I)=='.') THEN
         WRITE(CHID,'(A)') FN_INPUT(1:I-1)
         EXIT ROOTNAME
      ENDIF
   END DO ROOTNAME
ENDIF

FN_SMV=TRIM(CHID)//'.smv'
FN_GEOM(1)=TRIM(CHID)//'.ge'

END SUBROUTINE READ_HEAD

! ------------ SUBROUTINE CHECK_XB ---------------------------------

SUBROUTINE CHECK_XB(XB)
! Reorder an input sextuple XB if needed
REAL(EB) :: DUMMY,XB(6)
INTEGER  :: I
DO I=1,5,2
   IF (XB(I)>XB(I+1)) THEN
      DUMMY   = XB(I)
      XB(I)   = XB(I+1)
      XB(I+1) = DUMMY
   ENDIF
ENDDO
END SUBROUTINE CHECK_XB

! ------------ SUBROUTINE READ_MESH ---------------------------------

SUBROUTINE READ_MESH
INTEGER :: IBAR,JBAR,KBAR,J
INTEGER :: IOS, IZERO, N

REAL(EB) :: XB(6)
NAMELIST /MESH/ IBAR,JBAR,KBAR,XB

TYPE (MESH_TYPE), POINTER :: M=>NULL()

NMESHES = 0

REWIND(LU_INPUT)
COUNT_MESH_LOOP: DO
   CALL CHECKREAD('MESH',LU_INPUT,IOS)
   IF (IOS==1) EXIT COUNT_MESH_LOOP
   READ(LU_INPUT,MESH,END=15,ERR=16,IOSTAT=IOS)
   NMESHES      = NMESHES + 1
   16 IF (IOS>0) CALL SHUTDOWN('ERROR: Problem with MESH line.')
ENDDO COUNT_MESH_LOOP
15 CONTINUE

! Allocate parameters associated with the mesh.

ALLOCATE(MESHES(NMESHES),STAT=IZERO)
CALL ChkMemErr('READ','MESHES',IZERO)

! Read in the Mesh lines from Input file

REWIND(LU_INPUT)

IF (NMESHES<1) CALL SHUTDOWN('ERROR: No MESH line(s) defined.')

MESH_LOOP: DO N=1,NMESHES

   ! Set MESH defaults

   IBAR = 10
   JBAR = 10
   KBAR = 10
   XB(1) = 0._EB
   XB(2) = 1._EB
   XB(3) = 0._EB
   XB(4) = 1._EB
   XB(5) = 0._EB
   XB(6) = 1._EB

   CALL CHECKREAD('MESH',LU_INPUT,IOS)
   IF (IOS==1) EXIT MESH_LOOP
   READ(LU_INPUT,MESH)

   ! Reorder XB coordinates if necessary

   CALL CHECK_XB(XB)

   M => MESHES(N)
   DO J = 1, 6
      M%XB(J) = XB(J)
   END DO
   M%IBAR = IBAR
   M%JBAR = JBAR
   M%KBAR = KBAR

ENDDO MESH_LOOP

END SUBROUTINE READ_MESH

! ------------ SUBROUTINE COLOR2RGB ---------------------------------

SUBROUTINE COLOR2RGB(RGB,COLOR)
USE COMP_FUNCTIONS, ONLY:SHUTDOWN
! Translate character string of a color name to RGB value

INTEGER :: RGB(3)
CHARACTER(25) :: COLOR
CHARACTER(100) :: MESSAGE

SELECT CASE(COLOR)
CASE ('ALICE BLUE');RGB = (/240,248,255/)
CASE ('ANTIQUE WHITE');RGB = (/250,235,215/)
CASE ('ANTIQUE WHITE 1');RGB = (/255,239,219/)
CASE ('ANTIQUE WHITE 2');RGB = (/238,223,204/)
CASE ('ANTIQUE WHITE 3');RGB = (/205,192,176/)
CASE ('ANTIQUE WHITE 4');RGB = (/139,131,120/)
CASE ('AQUAMARINE');RGB = (/127,255,212/)
CASE ('AQUAMARINE 1');RGB = (/118,238,198/)
CASE ('AQUAMARINE 2');RGB = (/102,205,170/)
CASE ('AQUAMARINE 3');RGB = (/69,139,116/)
CASE ('AZURE');RGB = (/240,255,255/)
CASE ('AZURE 1');RGB = (/224,238,238/)
CASE ('AZURE 2');RGB = (/193,205,205/)
CASE ('AZURE 3');RGB = (/131,139,139/)
CASE ('BANANA');RGB = (/227,207,87/)
CASE ('BEIGE');RGB = (/245,245,220/)
CASE ('BISQUE');RGB = (/255,228,196/)
CASE ('BISQUE 1');RGB = (/238,213,183/)
CASE ('BISQUE 2');RGB = (/205,183,158/)
CASE ('BISQUE 3');RGB = (/139,125,107/)
CASE ('BLACK');RGB = (/0,0,0/)
CASE ('BLANCHED ALMOND');RGB = (/255,235,205/)
CASE ('BLUE');RGB = (/0,0,255/)
CASE ('BLUE 2');RGB = (/0,0,238/)
CASE ('BLUE 3');RGB = (/0,0,205/)
CASE ('BLUE 4');RGB = (/0,0,139/)
CASE ('BLUE VIOLET');RGB = (/138,43,226/)
CASE ('BRICK');RGB = (/156,102,31/)
CASE ('BROWN');RGB = (/165,42,42/)
CASE ('BROWN 1');RGB = (/255,64,64/)
CASE ('BROWN 2');RGB = (/238,59,59/)
CASE ('BROWN 3');RGB = (/205,51,51/)
CASE ('BROWN 4');RGB = (/139,35,35/)
CASE ('BURLY WOOD');RGB = (/222,184,135/)
CASE ('BURLY WOOD 1');RGB = (/255,211,155/)
CASE ('BURLY WOOD 2');RGB = (/238,197,145/)
CASE ('BURLY WOOD 3');RGB = (/205,170,125/)
CASE ('BURLY WOOD 4');RGB = (/139,115,85/)
CASE ('BURNT ORANGE');RGB = (/204,85,0/)
CASE ('BURNT SIENNA');RGB = (/138,54,15/)
CASE ('BURNT UMBER');RGB = (/138,51,36/)
CASE ('CADET BLUE');RGB = (/95,158,160/)
CASE ('CADET BLUE 1');RGB = (/152,245,255/)
CASE ('CADET BLUE 2');RGB = (/142,229,238/)
CASE ('CADET BLUE 3');RGB = (/122,197,205/)
CASE ('CADET BLUE 4');RGB = (/83,134,139/)
CASE ('CADMIUM ORANGE');RGB = (/255,97,3/)
CASE ('CADMIUM YELLOW');RGB = (/255,153,18/)
CASE ('CARROT');RGB = (/237,145,33/)
CASE ('CHARTREUSE');RGB = (/127,255,0/)
CASE ('CHARTREUSE 1');RGB = (/118,238,0/)
CASE ('CHARTREUSE 2');RGB = (/102,205,0/)
CASE ('CHARTREUSE 3');RGB = (/69,139,0/)
CASE ('CHOCOLATE');RGB = (/210,105,30/)
CASE ('CHOCOLATE 1');RGB = (/255,127,36/)
CASE ('CHOCOLATE 2');RGB = (/238,118,33/)
CASE ('CHOCOLATE 3');RGB = (/205,102,29/)
CASE ('CHOCOLATE 4');RGB = (/139,69,19/)
CASE ('COBALT');RGB = (/61,89,171/)
CASE ('COBALT GREEN');RGB = (/61,145,64/)
CASE ('COLD GREY');RGB = (/128,138,135/)
CASE ('CORAL');RGB = (/255,127,80/)
CASE ('CORAL 1');RGB = (/255,114,86/)
CASE ('CORAL 2');RGB = (/238,106,80/)
CASE ('CORAL 3');RGB = (/205,91,69/)
CASE ('CORAL 4');RGB = (/139,62,47/)
CASE ('CORNFLOWER BLUE');RGB = (/100,149,237/)
CASE ('CORNSILK');RGB = (/255,248,220/)
CASE ('CORNSILK 1');RGB = (/238,232,205/)
CASE ('CORNSILK 2');RGB = (/205,200,177/)
CASE ('CORNSILK 3');RGB = (/139,136,120/)
CASE ('CRIMSON');RGB = (/220,20,60/)
CASE ('CYAN');RGB = (/0,255,255/)
CASE ('CYAN 2');RGB = (/0,238,238/)
CASE ('CYAN 3');RGB = (/0,205,205/)
CASE ('CYAN 4');RGB = (/0,139,139/)
CASE ('DARK GOLDENROD');RGB = (/184,134,11/)
CASE ('DARK GOLDENROD 1');RGB = (/255,185,15/)
CASE ('DARK GOLDENROD 2');RGB = (/238,173,14/)
CASE ('DARK GOLDENROD 3');RGB = (/205,149,12/)
CASE ('DARK GOLDENROD 4');RGB = (/139,101,8/)
CASE ('DARK GRAY');RGB = (/169,169,169/)
CASE ('DARK GREEN');RGB = (/0,100,0/)
CASE ('DARK KHAKI');RGB = (/189,183,107/)
CASE ('DARK OLIVE GREEN');RGB = (/85,107,47/)
CASE ('DARK OLIVE GREEN 1');RGB = (/202,255,112/)
CASE ('DARK OLIVE GREEN 2');RGB = (/188,238,104/)
CASE ('DARK OLIVE GREEN 3');RGB = (/162,205,90/)
CASE ('DARK OLIVE GREEN 4');RGB = (/110,139,61/)
CASE ('DARK ORANGE');RGB = (/255,140,0/)
CASE ('DARK ORANGE 1');RGB = (/255,127,0/)
CASE ('DARK ORANGE 2');RGB = (/238,118,0/)
CASE ('DARK ORANGE 3');RGB = (/205,102,0/)
CASE ('DARK ORANGE 4');RGB = (/139,69,0/)
CASE ('DARK ORCHID');RGB = (/153,50,204/)
CASE ('DARK ORCHID 1');RGB = (/191,62,255/)
CASE ('DARK ORCHID 2');RGB = (/178,58,238/)
CASE ('DARK ORCHID 3');RGB = (/154,50,205/)
CASE ('DARK ORCHID 4');RGB = (/104,34,139/)
CASE ('DARK SALMON');RGB = (/233,150,122/)
CASE ('DARK SEA GREEN');RGB = (/143,188,143/)
CASE ('DARK SEA GREEN 1');RGB = (/193,255,193/)
CASE ('DARK SEA GREEN 2');RGB = (/180,238,180/)
CASE ('DARK SEA GREEN 3');RGB = (/155,205,155/)
CASE ('DARK SEA GREEN 4');RGB = (/105,139,105/)
CASE ('DARK SLATE BLUE');RGB = (/72,61,139/)
CASE ('DARK SLATE GRAY');RGB = (/47,79,79/)
CASE ('DARK SLATE GRAY 1');RGB = (/151,255,255/)
CASE ('DARK SLATE GRAY 2');RGB = (/141,238,238/)
CASE ('DARK SLATE GRAY 3');RGB = (/121,205,205/)
CASE ('DARK SLATE GRAY 4');RGB = (/82,139,139/)
CASE ('DARK TURQUOISE');RGB = (/0,206,209/)
CASE ('DARK VIOLET');RGB = (/148,0,211/)
CASE ('DEEP PINK');RGB = (/255,20,147/)
CASE ('DEEP PINK 1');RGB = (/238,18,137/)
CASE ('DEEP PINK 2');RGB = (/205,16,118/)
CASE ('DEEP PINK 3');RGB = (/139,10,80/)
CASE ('DEEP SKYBLUE');RGB = (/0,191,255/)
CASE ('DEEP SKYBLUE 1');RGB = (/0,178,238/)
CASE ('DEEP SKYBLUE 2');RGB = (/0,154,205/)
CASE ('DEEP SKYBLUE 3');RGB = (/0,104,139/)
CASE ('DIM GRAY');RGB = (/105,105,105/)
CASE ('DODGERBLUE');RGB = (/30,144,255/)
CASE ('DODGERBLUE 1');RGB = (/28,134,238/)
CASE ('DODGERBLUE 2');RGB = (/24,116,205/)
CASE ('DODGERBLUE 3');RGB = (/16,78,139/)
CASE ('EGGSHELL');RGB = (/252,230,201/)
CASE ('EMERALD GREEN');RGB = (/0,201,87/)
CASE ('FIREBRICK');RGB = (/178,34,34/)
CASE ('FIREBRICK 1');RGB = (/255,48,48/)
CASE ('FIREBRICK 2');RGB = (/238,44,44/)
CASE ('FIREBRICK 3');RGB = (/205,38,38/)
CASE ('FIREBRICK 4');RGB = (/139,26,26/)
CASE ('FLESH');RGB = (/255,125,64/)
CASE ('FLORAL WHITE');RGB = (/255,250,240/)
CASE ('FOREST GREEN');RGB = (/34,139,34/)
CASE ('GAINSBORO');RGB = (/220,220,220/)
CASE ('GHOST WHITE');RGB = (/248,248,255/)
CASE ('GOLD');RGB = (/255,215,0/)
CASE ('GOLD 1');RGB = (/238,201,0/)
CASE ('GOLD 2');RGB = (/205,173,0/)
CASE ('GOLD 3');RGB = (/139,117,0/)
CASE ('GOLDENROD');RGB = (/218,165,32/)
CASE ('GOLDENROD 1');RGB = (/255,193,37/)
CASE ('GOLDENROD 2');RGB = (/238,180,34/)
CASE ('GOLDENROD 3');RGB = (/205,155,29/)
CASE ('GOLDENROD 4');RGB = (/139,105,20/)
CASE ('GRAY');RGB = (/128,128,128/)
CASE ('GRAY 1');RGB = (/3,3,3/)
CASE ('GRAY 10');RGB = (/26,26,26/)
CASE ('GRAY 11');RGB = (/28,28,28/)
CASE ('GRAY 12');RGB = (/31,31,31/)
CASE ('GRAY 13');RGB = (/33,33,33/)
CASE ('GRAY 14');RGB = (/36,36,36/)
CASE ('GRAY 15');RGB = (/38,38,38/)
CASE ('GRAY 16');RGB = (/41,41,41/)
CASE ('GRAY 17');RGB = (/43,43,43/)
CASE ('GRAY 18');RGB = (/46,46,46/)
CASE ('GRAY 19');RGB = (/48,48,48/)
CASE ('GRAY 2');RGB = (/5,5,5/)
CASE ('GRAY 20');RGB = (/51,51,51/)
CASE ('GRAY 21');RGB = (/54,54,54/)
CASE ('GRAY 22');RGB = (/56,56,56/)
CASE ('GRAY 23');RGB = (/59,59,59/)
CASE ('GRAY 24');RGB = (/61,61,61/)
CASE ('GRAY 25');RGB = (/64,64,64/)
CASE ('GRAY 26');RGB = (/66,66,66/)
CASE ('GRAY 27');RGB = (/69,69,69/)
CASE ('GRAY 28');RGB = (/71,71,71/)
CASE ('GRAY 29');RGB = (/74,74,74/)
CASE ('GRAY 3');RGB = (/8,8,8/)
CASE ('GRAY 30');RGB = (/77,77,77/)
CASE ('GRAY 31');RGB = (/79,79,79/)
CASE ('GRAY 32');RGB = (/82,82,82/)
CASE ('GRAY 33');RGB = (/84,84,84/)
CASE ('GRAY 34');RGB = (/87,87,87/)
CASE ('GRAY 35');RGB = (/89,89,89/)
CASE ('GRAY 36');RGB = (/92,92,92/)
CASE ('GRAY 37');RGB = (/94,94,94/)
CASE ('GRAY 38');RGB = (/97,97,97/)
CASE ('GRAY 39');RGB = (/99,99,99/)
CASE ('GRAY 4');RGB = (/10,10,10/)
CASE ('GRAY 40');RGB = (/102,102,102/)
CASE ('GRAY 42');RGB = (/107,107,107/)
CASE ('GRAY 43');RGB = (/110,110,110/)
CASE ('GRAY 44');RGB = (/112,112,112/)
CASE ('GRAY 45');RGB = (/115,115,115/)
CASE ('GRAY 46');RGB = (/117,117,117/)
CASE ('GRAY 47');RGB = (/120,120,120/)
CASE ('GRAY 48');RGB = (/122,122,122/)
CASE ('GRAY 49');RGB = (/125,125,125/)
CASE ('GRAY 5');RGB = (/13,13,13/)
CASE ('GRAY 50');RGB = (/127,127,127/)
CASE ('GRAY 51');RGB = (/130,130,130/)
CASE ('GRAY 52');RGB = (/133,133,133/)
CASE ('GRAY 53');RGB = (/135,135,135/)
CASE ('GRAY 54');RGB = (/138,138,138/)
CASE ('GRAY 55');RGB = (/140,140,140/)
CASE ('GRAY 56');RGB = (/143,143,143/)
CASE ('GRAY 57');RGB = (/145,145,145/)
CASE ('GRAY 58');RGB = (/148,148,148/)
CASE ('GRAY 59');RGB = (/150,150,150/)
CASE ('GRAY 6');RGB = (/15,15,15/)
CASE ('GRAY 60');RGB = (/153,153,153/)
CASE ('GRAY 61');RGB = (/156,156,156/)
CASE ('GRAY 62');RGB = (/158,158,158/)
CASE ('GRAY 63');RGB = (/161,161,161/)
CASE ('GRAY 64');RGB = (/163,163,163/)
CASE ('GRAY 65');RGB = (/166,166,166/)
CASE ('GRAY 66');RGB = (/168,168,168/)
CASE ('GRAY 67');RGB = (/171,171,171/)
CASE ('GRAY 68');RGB = (/173,173,173/)
CASE ('GRAY 69');RGB = (/176,176,176/)
CASE ('GRAY 7');RGB = (/18,18,18/)
CASE ('GRAY 70');RGB = (/179,179,179/)
CASE ('GRAY 71');RGB = (/181,181,181/)
CASE ('GRAY 72');RGB = (/184,184,184/)
CASE ('GRAY 73');RGB = (/186,186,186/)
CASE ('GRAY 74');RGB = (/189,189,189/)
CASE ('GRAY 75');RGB = (/191,191,191/)
CASE ('GRAY 76');RGB = (/194,194,194/)
CASE ('GRAY 77');RGB = (/196,196,196/)
CASE ('GRAY 78');RGB = (/199,199,199/)
CASE ('GRAY 79');RGB = (/201,201,201/)
CASE ('GRAY 8');RGB = (/20,20,20/)
CASE ('GRAY 80');RGB = (/204,204,204/)
CASE ('GRAY 81');RGB = (/207,207,207/)
CASE ('GRAY 82');RGB = (/209,209,209/)
CASE ('GRAY 83');RGB = (/212,212,212/)
CASE ('GRAY 84');RGB = (/214,214,214/)
CASE ('GRAY 85');RGB = (/217,217,217/)
CASE ('GRAY 86');RGB = (/219,219,219/)
CASE ('GRAY 87');RGB = (/222,222,222/)
CASE ('GRAY 88');RGB = (/224,224,224/)
CASE ('GRAY 89');RGB = (/227,227,227/)
CASE ('GRAY 9');RGB = (/23,23,23/)
CASE ('GRAY 90');RGB = (/229,229,229/)
CASE ('GRAY 91');RGB = (/232,232,232/)
CASE ('GRAY 92');RGB = (/235,235,235/)
CASE ('GRAY 93');RGB = (/237,237,237/)
CASE ('GRAY 94');RGB = (/240,240,240/)
CASE ('GRAY 95');RGB = (/242,242,242/)
CASE ('GRAY 97');RGB = (/247,247,247/)
CASE ('GRAY 98');RGB = (/250,250,250/)
CASE ('GRAY 99');RGB = (/252,252,252/)
CASE ('GREEN');RGB = (/0,255,0/)
CASE ('GREEN 2');RGB = (/0,238,0/)
CASE ('GREEN 3');RGB = (/0,205,0/)
CASE ('GREEN 4');RGB = (/0,139,0/)
CASE ('GREEN YELLOW');RGB = (/173,255,47/)
CASE ('HONEYDEW');RGB = (/240,255,240/)
CASE ('HONEYDEW 1');RGB = (/224,238,224/)
CASE ('HONEYDEW 2');RGB = (/193,205,193/)
CASE ('HONEYDEW 3');RGB = (/131,139,131/)
CASE ('HOT PINK');RGB = (/255,105,180/)
CASE ('HOT PINK 1');RGB = (/255,110,180/)
CASE ('HOT PINK 2');RGB = (/238,106,167/)
CASE ('HOT PINK 3');RGB = (/205,96,144/)
CASE ('HOT PINK 4');RGB = (/139,58,98/)
CASE ('INDIAN RED');RGB = (/205,92,92/)
CASE ('INDIAN RED 1');RGB = (/255,106,106/)
CASE ('INDIAN RED 2');RGB = (/238,99,99/)
CASE ('INDIAN RED 3');RGB = (/205,85,85/)
CASE ('INDIAN RED 4');RGB = (/139,58,58/)
CASE ('INDIGO');RGB = (/75,0,130/)
CASE ('IVORY');RGB = (/255,255,240/)
CASE ('IVORY 1');RGB = (/238,238,224/)
CASE ('IVORY 2');RGB = (/205,205,193/)
CASE ('IVORY 3');RGB = (/139,139,131/)
CASE ('IVORY BLACK');RGB = (/41,36,33/)
CASE ('KELLY GREEN');RGB = (/0,128,0/)
CASE ('KHAKI');RGB = (/240,230,140/)
CASE ('KHAKI 1');RGB = (/255,246,143/)
CASE ('KHAKI 2');RGB = (/238,230,133/)
CASE ('KHAKI 3');RGB = (/205,198,115/)
CASE ('KHAKI 4');RGB = (/139,134,78/)
CASE ('LAVENDER');RGB = (/230,230,250/)
CASE ('LAVENDER BLUSH');RGB = (/255,240,245/)
CASE ('LAVENDER BLUSH 1');RGB = (/238,224,229/)
CASE ('LAVENDER BLUSH 2');RGB = (/205,193,197/)
CASE ('LAVENDER BLUSH 3');RGB = (/139,131,134/)
CASE ('LAWN GREEN');RGB = (/124,252,0/)
CASE ('LEMON CHIFFON');RGB = (/255,250,205/)
CASE ('LEMON CHIFFON 1');RGB = (/238,233,191/)
CASE ('LEMON CHIFFON 2');RGB = (/205,201,165/)
CASE ('LEMON CHIFFON 3');RGB = (/139,137,112/)
CASE ('LIGHT BLUE');RGB = (/173,216,230/)
CASE ('LIGHT BLUE 1');RGB = (/191,239,255/)
CASE ('LIGHT BLUE 2');RGB = (/178,223,238/)
CASE ('LIGHT BLUE 3');RGB = (/154,192,205/)
CASE ('LIGHT BLUE 4');RGB = (/104,131,139/)
CASE ('LIGHT CORAL');RGB = (/240,128,128/)
CASE ('LIGHT CYAN');RGB = (/224,255,255/)
CASE ('LIGHT CYAN 1');RGB = (/209,238,238/)
CASE ('LIGHT CYAN 2');RGB = (/180,205,205/)
CASE ('LIGHT CYAN 3');RGB = (/122,139,139/)
CASE ('LIGHT GOLDENROD');RGB = (/255,236,139/)
CASE ('LIGHT GOLDENROD 1');RGB = (/238,220,130/)
CASE ('LIGHT GOLDENROD 2');RGB = (/205,190,112/)
CASE ('LIGHT GOLDENROD 3');RGB = (/139,129,76/)
CASE ('LIGHT GOLDENROD YELLOW');RGB = (/250,250,210/)
CASE ('LIGHT GREY');RGB = (/211,211,211/)
CASE ('LIGHT PINK');RGB = (/255,182,193/)
CASE ('LIGHT PINK 1');RGB = (/255,174,185/)
CASE ('LIGHT PINK 2');RGB = (/238,162,173/)
CASE ('LIGHT PINK 3');RGB = (/205,140,149/)
CASE ('LIGHT PINK 4');RGB = (/139,95,101/)
CASE ('LIGHT SALMON');RGB = (/255,160,122/)
CASE ('LIGHT SALMON 1');RGB = (/238,149,114/)
CASE ('LIGHT SALMON 2');RGB = (/205,129,98/)
CASE ('LIGHT SALMON 3');RGB = (/139,87,66/)
CASE ('LIGHT SEA GREEN');RGB = (/32,178,170/)
CASE ('LIGHT SKY BLUE');RGB = (/135,206,250/)
CASE ('LIGHT SKY BLUE 1');RGB = (/176,226,255/)
CASE ('LIGHT SKY BLUE 2');RGB = (/164,211,238/)
CASE ('LIGHT SKY BLUE 3');RGB = (/141,182,205/)
CASE ('LIGHT SKY BLUE 4');RGB = (/96,123,139/)
CASE ('LIGHT SLATE BLUE');RGB = (/132,112,255/)
CASE ('LIGHT SLATE GRAY');RGB = (/119,136,153/)
CASE ('LIGHT STEEL BLUE');RGB = (/176,196,222/)
CASE ('LIGHT STEEL BLUE 1');RGB = (/202,225,255/)
CASE ('LIGHT STEEL BLUE 2');RGB = (/188,210,238/)
CASE ('LIGHT STEEL BLUE 3');RGB = (/162,181,205/)
CASE ('LIGHT STEEL BLUE 4');RGB = (/110,123,139/)
CASE ('LIGHT YELLOW 1');RGB = (/255,255,224/)
CASE ('LIGHT YELLOW 2');RGB = (/238,238,209/)
CASE ('LIGHT YELLOW 3');RGB = (/205,205,180/)
CASE ('LIGHT YELLOW 4');RGB = (/139,139,122/)
CASE ('LIME GREEN');RGB = (/50,205,50/)
CASE ('LINEN');RGB = (/250,240,230/)
CASE ('MAGENTA');RGB = (/255,0,255/)
CASE ('MAGENTA 2');RGB = (/238,0,238/)
CASE ('MAGENTA 3');RGB = (/205,0,205/)
CASE ('MAGENTA 4');RGB = (/139,0,139/)
CASE ('MANGANESE BLUE');RGB = (/3,168,158/)
CASE ('MAROON');RGB = (/128,0,0/)
CASE ('MAROON 1');RGB = (/255,52,179/)
CASE ('MAROON 2');RGB = (/238,48,167/)
CASE ('MAROON 3');RGB = (/205,41,144/)
CASE ('MAROON 4');RGB = (/139,28,98/)
CASE ('MEDIUM ORCHID');RGB = (/186,85,211/)
CASE ('MEDIUM ORCHID 1');RGB = (/224,102,255/)
CASE ('MEDIUM ORCHID 2');RGB = (/209,95,238/)
CASE ('MEDIUM ORCHID 3');RGB = (/180,82,205/)
CASE ('MEDIUM ORCHID 4');RGB = (/122,55,139/)
CASE ('MEDIUM PURPLE');RGB = (/147,112,219/)
CASE ('MEDIUM PURPLE 1');RGB = (/171,130,255/)
CASE ('MEDIUM PURPLE 2');RGB = (/159,121,238/)
CASE ('MEDIUM PURPLE 3');RGB = (/137,104,205/)
CASE ('MEDIUM PURPLE 4');RGB = (/93,71,139/)
CASE ('MEDIUM SEA GREEN');RGB = (/60,179,113/)
CASE ('MEDIUM SLATE BLUE');RGB = (/123,104,238/)
CASE ('MEDIUM SPRING GREEN');RGB = (/0,250,154/)
CASE ('MEDIUM TURQUOISE');RGB = (/72,209,204/)
CASE ('MEDIUM VIOLET RED');RGB = (/199,21,133/)
CASE ('MELON');RGB = (/227,168,105/)
CASE ('MIDNIGHT BLUE');RGB = (/25,25,112/)
CASE ('MINT');RGB = (/189,252,201/)
CASE ('MINT CREAM');RGB = (/245,255,250/)
CASE ('MISTY ROSE');RGB = (/255,228,225/)
CASE ('MISTY ROSE 1');RGB = (/238,213,210/)
CASE ('MISTY ROSE 2');RGB = (/205,183,181/)
CASE ('MISTY ROSE 3');RGB = (/139,125,123/)
CASE ('MOCCASIN');RGB = (/255,228,181/)
CASE ('NAVAJO WHITE');RGB = (/255,222,173/)
CASE ('NAVAJO WHITE 1');RGB = (/238,207,161/)
CASE ('NAVAJO WHITE 2');RGB = (/205,179,139/)
CASE ('NAVAJO WHITE 3');RGB = (/139,121,94/)
CASE ('NAVY');RGB = (/0,0,128/)
CASE ('OLD LACE');RGB = (/253,245,230/)
CASE ('OLIVE');RGB = (/128,128,0/)
CASE ('OLIVE DRAB');RGB = (/192,255,62/)
CASE ('OLIVE DRAB 1');RGB = (/179,238,58/)
CASE ('OLIVE DRAB 2');RGB = (/154,205,50/)
CASE ('OLIVE DRAB 3');RGB = (/105,139,34/)
CASE ('ORANGE');RGB = (/255,128,0/)
CASE ('ORANGE 1');RGB = (/255,165,0/)
CASE ('ORANGE 2');RGB = (/238,154,0/)
CASE ('ORANGE 3');RGB = (/205,133,0/)
CASE ('ORANGE 4');RGB = (/139,90,0/)
CASE ('ORANGE RED');RGB = (/255,69,0/)
CASE ('ORANGE RED 1');RGB = (/238,64,0/)
CASE ('ORANGE RED 2');RGB = (/205,55,0/)
CASE ('ORANGE RED 3');RGB = (/139,37,0/)
CASE ('ORCHID');RGB = (/218,112,214/)
CASE ('ORCHID 1');RGB = (/255,131,250/)
CASE ('ORCHID 2');RGB = (/238,122,233/)
CASE ('ORCHID 3');RGB = (/205,105,201/)
CASE ('ORCHID 4');RGB = (/139,71,137/)
CASE ('PALE GOLDENROD');RGB = (/238,232,170/)
CASE ('PALE GREEN');RGB = (/152,251,152/)
CASE ('PALE GREEN 1');RGB = (/154,255,154/)
CASE ('PALE GREEN 2');RGB = (/144,238,144/)
CASE ('PALE GREEN 3');RGB = (/124,205,124/)
CASE ('PALE GREEN 4');RGB = (/84,139,84/)
CASE ('PALE TURQUOISE');RGB = (/187,255,255/)
CASE ('PALE TURQUOISE 1');RGB = (/174,238,238/)
CASE ('PALE TURQUOISE 2');RGB = (/150,205,205/)
CASE ('PALE TURQUOISE 3');RGB = (/102,139,139/)
CASE ('PALE VIOLET RED');RGB = (/219,112,147/)
CASE ('PALE VIOLET RED 1');RGB = (/255,130,171/)
CASE ('PALE VIOLET RED 2');RGB = (/238,121,159/)
CASE ('PALE VIOLET RED 3');RGB = (/205,104,137/)
CASE ('PALE VIOLET RED 4');RGB = (/139,71,93/)
CASE ('PAPAYA WHIP');RGB = (/255,239,213/)
CASE ('PEACH PUFF');RGB = (/255,218,185/)
CASE ('PEACH PUFF 1');RGB = (/238,203,173/)
CASE ('PEACH PUFF 2');RGB = (/205,175,149/)
CASE ('PEACH PUFF 3');RGB = (/139,119,101/)
CASE ('PEACOCK');RGB = (/51,161,201/)
CASE ('PINK');RGB = (/255,192,203/)
CASE ('PINK 1');RGB = (/255,181,197/)
CASE ('PINK 2');RGB = (/238,169,184/)
CASE ('PINK 3');RGB = (/205,145,158/)
CASE ('PINK 4');RGB = (/139,99,108/)
CASE ('PLUM');RGB = (/221,160,221/)
CASE ('PLUM 1');RGB = (/255,187,255/)
CASE ('PLUM 2');RGB = (/238,174,238/)
CASE ('PLUM 3');RGB = (/205,150,205/)
CASE ('PLUM 4');RGB = (/139,102,139/)
CASE ('POWDER BLUE');RGB = (/176,224,230/)
CASE ('PURPLE');RGB = (/128,0,128/)
CASE ('PURPLE 1');RGB = (/155,48,255/)
CASE ('PURPLE 2');RGB = (/145,44,238/)
CASE ('PURPLE 3');RGB = (/125,38,205/)
CASE ('PURPLE 4');RGB = (/85,26,139/)
CASE ('RASPBERRY');RGB = (/135,38,87/)
CASE ('RAW SIENNA');RGB = (/199,97,20/)
CASE ('RED');RGB = (/255,0,0/)
CASE ('RED 1');RGB = (/238,0,0/)
CASE ('RED 2');RGB = (/205,0,0/)
CASE ('RED 3');RGB = (/139,0,0/)
CASE ('ROSY BROWN');RGB = (/188,143,143/)
CASE ('ROSY BROWN 1');RGB = (/255,193,193/)
CASE ('ROSY BROWN 2');RGB = (/238,180,180/)
CASE ('ROSY BROWN 3');RGB = (/205,155,155/)
CASE ('ROSY BROWN 4');RGB = (/139,105,105/)
CASE ('ROYAL BLUE');RGB = (/65,105,225/)
CASE ('ROYAL BLUE 1');RGB = (/72,118,255/)
CASE ('ROYAL BLUE 2');RGB = (/67,110,238/)
CASE ('ROYAL BLUE 3');RGB = (/58,95,205/)
CASE ('ROYAL BLUE 4');RGB = (/39,64,139/)
CASE ('SALMON');RGB = (/250,128,114/)
CASE ('SALMON 1');RGB = (/255,140,105/)
CASE ('SALMON 2');RGB = (/238,130,98/)
CASE ('SALMON 3');RGB = (/205,112,84/)
CASE ('SALMON 4');RGB = (/139,76,57/)
CASE ('SANDY BROWN');RGB = (/244,164,96/)
CASE ('SAP GREEN');RGB = (/48,128,20/)
CASE ('SEA GREEN');RGB = (/84,255,159/)
CASE ('SEA GREEN 1');RGB = (/78,238,148/)
CASE ('SEA GREEN 2');RGB = (/67,205,128/)
CASE ('SEA GREEN 3');RGB = (/46,139,87/)
CASE ('SEASHELL');RGB = (/255,245,238/)
CASE ('SEASHELL 1');RGB = (/238,229,222/)
CASE ('SEASHELL 2');RGB = (/205,197,191/)
CASE ('SEASHELL 3');RGB = (/139,134,130/)
CASE ('SEPIA');RGB = (/94,38,18/)
CASE ('SIENNA');RGB = (/160,82,45/)
CASE ('SIENNA 1');RGB = (/255,130,71/)
CASE ('SIENNA 2');RGB = (/238,121,66/)
CASE ('SIENNA 3');RGB = (/205,104,57/)
CASE ('SIENNA 4');RGB = (/139,71,38/)
CASE ('SILVER');RGB = (/192,192,192/)
CASE ('SKY BLUE');RGB = (/135,206,235/)
CASE ('SKY BLUE 1');RGB = (/135,206,255/)
CASE ('SKY BLUE 2');RGB = (/126,192,238/)
CASE ('SKY BLUE 3');RGB = (/108,166,205/)
CASE ('SKY BLUE 4');RGB = (/74,112,139/)
CASE ('SLATE BLUE');RGB = (/106,90,205/)
CASE ('SLATE BLUE 1');RGB = (/131,111,255/)
CASE ('SLATE BLUE 2');RGB = (/122,103,238/)
CASE ('SLATE BLUE 3');RGB = (/105,89,205/)
CASE ('SLATE BLUE 4');RGB = (/71,60,139/)
CASE ('SLATE GRAY');RGB = (/112,128,144/)
CASE ('SLATE GRAY 1');RGB = (/198,226,255/)
CASE ('SLATE GRAY 2');RGB = (/185,211,238/)
CASE ('SLATE GRAY 3');RGB = (/159,182,205/)
CASE ('SLATE GRAY 4');RGB = (/108,123,139/)
CASE ('SNOW');RGB = (/255,250,250/)
CASE ('SNOW 1');RGB = (/238,233,233/)
CASE ('SNOW 2');RGB = (/205,201,201/)
CASE ('SNOW 3');RGB = (/139,137,137/)
CASE ('SPRING GREEN');RGB = (/0,255,127/)
CASE ('SPRING GREEN 1');RGB = (/0,238,118/)
CASE ('SPRING GREEN 2');RGB = (/0,205,102/)
CASE ('SPRING GREEN 3');RGB = (/0,139,69/)
CASE ('STEEL BLUE');RGB = (/70,130,180/)
CASE ('STEEL BLUE 1');RGB = (/99,184,255/)
CASE ('STEEL BLUE 2');RGB = (/92,172,238/)
CASE ('STEEL BLUE 3');RGB = (/79,148,205/)
CASE ('STEEL BLUE 4');RGB = (/54,100,139/)
CASE ('TAN');RGB = (/210,180,140/)
CASE ('TAN 1');RGB = (/255,165,79/)
CASE ('TAN 2');RGB = (/238,154,73/)
CASE ('TAN 3');RGB = (/205,133,63/)
CASE ('TAN 4');RGB = (/139,90,43/)
CASE ('TEAL');RGB = (/0,128,128/)
CASE ('THISTLE');RGB = (/216,191,216/)
CASE ('THISTLE 1');RGB = (/255,225,255/)
CASE ('THISTLE 2');RGB = (/238,210,238/)
CASE ('THISTLE 3');RGB = (/205,181,205/)
CASE ('THISTLE 4');RGB = (/139,123,139/)
CASE ('TOMATO');RGB = (/255,99,71/)
CASE ('TOMATO 1');RGB = (/238,92,66/)
CASE ('TOMATO 2');RGB = (/205,79,57/)
CASE ('TOMATO 3');RGB = (/139,54,38/)
CASE ('TURQUOISE');RGB = (/64,224,208/)
CASE ('TURQUOISE 1');RGB = (/0,245,255/)
CASE ('TURQUOISE 2');RGB = (/0,229,238/)
CASE ('TURQUOISE 3');RGB = (/0,197,205/)
CASE ('TURQUOISE 4');RGB = (/0,134,139/)
CASE ('TURQUOISE BLUE');RGB = (/0,199,140/)
CASE ('VIOLET');RGB = (/238,130,238/)
CASE ('VIOLET RED');RGB = (/208,32,144/)
CASE ('VIOLET RED 1');RGB = (/255,62,150/)
CASE ('VIOLET RED 2');RGB = (/238,58,140/)
CASE ('VIOLET RED 3');RGB = (/205,50,120/)
CASE ('VIOLET RED 4');RGB = (/139,34,82/)
CASE ('WARM GREY');RGB = (/128,128,105/)
CASE ('WHEAT');RGB = (/245,222,179/)
CASE ('WHEAT 1');RGB = (/255,231,186/)
CASE ('WHEAT 2');RGB = (/238,216,174/)
CASE ('WHEAT 3');RGB = (/205,186,150/)
CASE ('WHEAT 4');RGB = (/139,126,102/)
CASE ('WHITE');RGB = (/255,255,255/)
CASE ('WHITE SMOKE');RGB = (/245,245,245/)
CASE ('YELLOW');RGB = (/255,255,0/)
CASE ('YELLOW 1');RGB = (/238,238,0/)
CASE ('YELLOW 2');RGB = (/205,205,0/)
CASE ('YELLOW 3');RGB = (/139,139,0/)

CASE DEFAULT
   WRITE(MESSAGE,'(A,A,A)') "ERROR: The COLOR, ", TRIM(COLOR),", is not a defined color"
   CALL SHUTDOWN(MESSAGE)      
END SELECT

END SUBROUTINE COLOR2RGB

! ------------ INTEGER FUNCTION GET_SURF_INDEX ---------------------------------

INTEGER FUNCTION GET_SURF_INDEX(ID)
CHARACTER(30), INTENT(IN) :: ID
INTEGER :: N

DO N = 1, N_SURF
   IF( TRIM(SURFACE(N)%ID) .NE. TRIM(ID) )CYCLE
   GET_SURF_INDEX = N
   RETURN
END DO
GET_SURF_INDEX = 0
END FUNCTION GET_SURF_INDEX

! ------------ SUBROUTINE READ_SURF ---------------------------------

SUBROUTINE READ_SURF

INTEGER :: RGB(3)
NAMELIST /SURF/ ID,RGB

INTEGER :: IOS, IZERO, N
CHARACTER(100) :: MESSAGE
TYPE(SURF_TYPE), POINTER :: SF
CHARACTER(25) :: COLOR

! Count the SURF lines in the input file

REWIND(LU_INPUT)
N_SURF = 0
COUNT_SURF_LOOP: DO
   CALL CHECKREAD('SURF',LU_INPUT,IOS)
   IF (IOS==1) EXIT COUNT_SURF_LOOP
   READ(LU_INPUT,SURF,ERR=34,IOSTAT=IOS)
   N_SURF = N_SURF + 1
   34 IF (IOS>0) THEN
         WRITE(MESSAGE,'(A,I3)') 'ERROR: Problem with SURF number', N_SURF+1
         CALL SHUTDOWN(MESSAGE)
      ENDIF
ENDDO COUNT_SURF_LOOP

! Allocate the SURFACE derived type, leaving space for SURF entries not defined explicitly by the user

ALLOCATE(SURFACE(0:N_SURF+1),STAT=IZERO)
CALL ChkMemErr('READ','SURFACE',IZERO)

! Read the SURF lines

REWIND(LU_INPUT)
READ_SURF_LOOP: DO N=0,N_SURF

   SF => SURFACE(N)
   
   CALL CHECKREAD('SURF',LU_INPUT,IOS)

   COLOR                   = 'null'
   ID                      = 'null'
   RGB                     = -1

   IF(N.NE.0)READ(LU_INPUT,SURF)

   IF (COLOR/='null') THEN
      CALL COLOR2RGB(RGB,COLOR)
   ENDIF
   IF (ANY(RGB< 0)) THEN
      RGB(1) = 255
      RGB(2) = 204
      RGB(3) = 102
   ENDIF
   SF%RGB                  = RGB
   SF%ID = TRIM(ID)

ENDDO READ_SURF_LOOP

END SUBROUTINE READ_SURF

! ------------ SUBROUTINE WRITE_SMV ---------------------------------

SUBROUTINE READ_TIME

INTEGER :: IOS
NAMELIST /TIME/ T_BEGIN,T_END

T_BEGIN              = 0._EB
T_END                = 1._EB

REWIND(LU_INPUT)
READ_TIME_LOOP: DO
   CALL CHECKREAD('TIME',LU_INPUT,IOS)
   IF (IOS==1) EXIT READ_TIME_LOOP
   READ(LU_INPUT,TIME,END=21,ERR=22,IOSTAT=IOS)
   22 IF (IOS>0) CALL SHUTDOWN('ERROR: Problem with TIME line')
ENDDO READ_TIME_LOOP
21 REWIND(LU_INPUT)

END SUBROUTINE READ_TIME

END MODULE READ_INPUT

! ------------ SUBROUTINE WRITE_SMV ---------------------------------

SUBROUTINE WRITE_SMV
USE GLOBAL_CONSTANTS
USE TYPES
USE READ_INPUT
IMPLICIT NONE
SAVE

INTEGER :: N,I
TYPE (MESH_TYPE), POINTER :: M=>NULL()
TYPE (SURF_TYPE), POINTER :: SF=>NULL()

OPEN(LU_SMV,FILE=FN_SMV)

WRITE(LU_SMV,'(/A)') 'CHID'
WRITE(LU_SMV,'(1X,A)') TRIM(CHID)

DO N = 1, NMESHES
   M=>MESHES(N)
   
   WRITE(LU_SMV,'(/A)') 'PDIM'
   WRITE(LU_SMV,'(6F14.5)') (M%XB(I),I=1,6)
   
   WRITE(LU_SMV,'(/A,3X,A,1X,I10)') 'GRID','MESH',N
   WRITE(LU_SMV,'(3I5)') M%IBAR,M%JBAR,M%KBAR
   
   WRITE(LU_SMV,'(/A)') 'TRNX'
   WRITE(LU_SMV,'(I5)') 0
   DO I=0,M%IBAR
      WRITE(LU_SMV,'(I5,F14.5)') I,((M%IBAR-I)*M%XB(1)+I*M%XB(2))/REAL(M%IBAR,EB)
   ENDDO
   
   WRITE(LU_SMV,'(/A)') 'TRNY'
   WRITE(LU_SMV,'(I5)') 0
   DO I=0,M%JBAR
      WRITE(LU_SMV,'(I5,F14.5)') I,((M%JBAR-I)*M%XB(3)+I*M%XB(4))/REAL(M%JBAR,EB)
   ENDDO

   WRITE(LU_SMV,'(/A)') 'TRNZ'
   WRITE(LU_SMV,'(I5)') 0
   DO I=0,M%KBAR
      WRITE(LU_SMV,'(I5,F14.5)') I,((M%KBAR-I)*M%XB(5)+I*M%XB(6))/REAL(M%KBAR,EB)
   ENDDO
   
   WRITE(LU_SMV,'(/A)') 'VENT'
   WRITE(LU_SMV,'(2I5)') 0,0

   WRITE(LU_SMV,'(/A)') 'OBST'
   WRITE(LU_SMV,'(I5)') 0

END DO


WRITE(LU_SMV,'(/A)') 'SURFDEF'
WRITE(LU_SMV,'(1X,A)') SURFACE(0)%ID
 
DO N=0,N_SURF
   SF => SURFACE(N)
   WRITE(LU_SMV,'(/A)') 'SURFACE'
   WRITE(LU_SMV,'(1X,A)') SURFACE(N)%ID
   WRITE(LU_SMV,'(2F8.2)') 5000.,1.0
   WRITE(LU_SMV,'(I2,6F13.5)') 0,1.0,1.0,REAL(SF%RGB,FB)/255._FB,1.0
   WRITE(LU_SMV,'(1X,A)') 'null'
ENDDO


WRITE(LU_SMV,'(/A)') 'GEOM'
WRITE(LU_SMV,'(1X,A)') FN_GEOM(1)

END SUBROUTINE WRITE_SMV
