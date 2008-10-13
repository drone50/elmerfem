# ElmerGUI.pro for MinGW with VTK

TEMPLATE = app
TARGET = ElmerGUI
DEPENDPATH += . src forms plugins
INCLUDEPATH += .
MOC_DIR = ./tmp
OBJECTS_DIR = ./tmp
RCC_DIR = ./tmp
UI_DIR = ./tmp

QMAKE_CXXFLAGS = -O2 -Wno-deprecated
QMAKE_CXXFLAGS_WARN_ON = 

# For process info query:
LIBS += -lpsapi

# QT
QT += opengl xml script
CONFIG += uitools

# QWT (you may need to edit this)
INCLUDEPATH += /c/Qwt-5.0.2/include
LIBPATH += /c/Qwt-5.0.2/lib
LIBS += -lqwt5

# QVTK (you may need to edit this)
DEFINES += VTKPOST
INCLUDEPATH += /c/VTK/include/vtk-5.2
LIBPATH += /c/VTK/lib/vtk-5.2
LIBS += -lvtkCommon -lvtkRendering -lvtkFiltering -lvtkGraphics -lvtkIO -lQVTK

# MATC (you may need to edit this)
DEFINES += MATC
LIBPATH += /c/Elmer5.4/lib
LIBS += -lmatc

# Input
HEADERS += src/bodypropertyeditor.h \
           src/boundarydivision.h \
           src/boundarypropertyeditor.h \
           src/checkmpi.h \
           src/convergenceview.h \
           src/dynamiceditor.h \
           src/edfeditor.h \
           src/egini.h \
           src/generalsetup.h \
           src/glcontrol.h \
           src/glwidget.h \
           src/helpers.h \
           src/mainwindow.h \
           src/materiallibrary.h \
           src/maxlimits.h \
           src/meshcontrol.h \
           src/meshingthread.h \
           src/meshtype.h \
           src/meshutils.h \
           src/operation.h \
           src/parallel.h \
           src/projectio.h \
           src/sifgenerator.h \
           src/sifwindow.h \
           src/solverparameters.h \
           src/summaryeditor.h \
           plugins/egconvert.h \
           plugins/egdef.h \
           plugins/egmain.h \
           plugins/egmesh.h \
           plugins/egnative.h \
           plugins/egtypes.h \
           plugins/egutils.h \
           plugins/elmergrid_api.h \
           plugins/nglib.h \
           plugins/nglib_api.h \
           plugins/tetgen.h \
           plugins/tetlib_api.h \
           vtkpost/vtkpost.h \
           vtkpost/isosurface.h \
           vtkpost/isocontour.h \
           vtkpost/epmesh.h \
           vtkpost/colorbar.h \
           vtkpost/surface.h \
           vtkpost/preferences.h \
           vtkpost/vector.h \
           vtkpost/matc.h
FORMS += forms/bodypropertyeditor.ui \
         forms/boundarydivision.ui \
         forms/boundarypropertyeditor.ui \
         forms/generalsetup.ui \
         forms/glcontrol.ui \
         forms/materiallibrary.ui \
         forms/meshcontrol.ui \
         forms/parallel.ui \
         forms/solverparameters.ui \
         forms/summaryeditor.ui \
         vtkpost/isosurface.ui \
         vtkpost/isocontour.ui \
         vtkpost/colorbar.ui \
         vtkpost/surface.ui \
         vtkpost/preferences.ui \
         vtkpost/vector.ui \
         vtkpost/matc.ui
SOURCES += src/bodypropertyeditor.cpp \
           src/boundarydivision.cpp \
           src/boundarypropertyeditor.cpp \
           src/checkmpi.cpp \
           src/convergenceview.cpp \
           src/dynamiceditor.cpp \
           src/edfeditor.cpp \
           src/egini.cpp \
           src/generalsetup.cpp \
           src/glcontrol.cpp \
           src/glwidget.cpp \
           src/helpers.cpp \
           src/main.cpp \
           src/mainwindow.cpp \
           src/materiallibrary.cpp \
           src/maxlimits.cpp \
           src/meshcontrol.cpp \
           src/meshingthread.cpp \
           src/meshtype.cpp \
           src/meshutils.cpp \
           src/operation.cpp \
           src/parallel.cpp \
           src/projectio.cpp \
           src/sifgenerator.cpp \
           src/sifwindow.cpp \
           src/solverparameters.cpp \
           src/summaryeditor.cpp \
           plugins/egconvert.cpp \
           plugins/egmain.cpp \
           plugins/egmesh.cpp \
           plugins/egnative.cpp \
           plugins/egutils.cpp \
           plugins/elmergrid_api.cpp \
           plugins/nglib_api.cpp \
           plugins/tetlib_api.cpp \
           vtkpost/vtkpost.cpp \
           vtkpost/isosurface.cpp \
           vtkpost/isocontour.cpp \
           vtkpost/epmesh.cpp \
           vtkpost/colorbar.cpp \
           vtkpost/surface.cpp \
           vtkpost/preferences.cpp \
           vtkpost/vector.cpp \
           vtkpost/matc.cpp
RESOURCES += ElmerGUI.qrc
RC_FILE += ElmerGUI.rc   
