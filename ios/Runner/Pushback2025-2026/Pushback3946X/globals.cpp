#include "api.h"
#include "pros/adi.hpp"
#include "pros/motor_group.hpp"
#include "pros/optical.hpp"
#include "pros/rotation.hpp"
#include "pros/rtos.hpp"
#include "subSystems.hpp"

//Drive Motor Groups
pros::MotorGroup leftMtrs({-5, -11, -9});
pros::MotorGroup rightMtrs({2,3,10});

//Intake Motor
pros::Motor intakeMtr(6);

//Lady B Motors
pros::MotorGroup ladyBMtrs({4, -8});

//Mogo Mech Pistons
pros::adi::DigitalOut mogoPistons('F');

//IMU
pros::IMU IMU1(18);

//IMU
pros::IMU IMU2(21);

//Doinker Piston
pros::adi::DigitalOut doinkerPiston('E');

//Intake Color Sensor
pros::Optical intakeColorSensor(3);

//Rotation sensor on Backpack
pros::Rotation ladyBRotation(1);

//odom
//pros::Rotation odomSens(-18);