#include "subSystems.hpp"
#include "atomic"
#include "main.h"

namespace drive{
    std::atomic<int> leftSpeed = 0;
    std::atomic<int> rightSpeed = 0;
    /*
    Updates Drive to target voltages
    */
    void daemon(){
        while(true){
             leftMtrs.move_voltage(leftSpeed);
             rightMtrs.move_voltage(rightSpeed);
             
             pros::delay(20);
        }
    }
    /*
    Drive the left side of the base at a specified speed
    */
    void driveLeftAt(int leftVoltage){
        leftSpeed = leftVoltage;
    }
    /*
    Drive the right side of the base at a specific speed
    */
    void driveRightAt(int rightVoltage){
        rightSpeed = rightVoltage;
    }
    /*
    Drive the base a specified speeds for left and right
    */
    void driveAt(int leftVoltage, int rightVoltage){
        driveLeftAt(leftVoltage);
        driveRightAt(rightVoltage);
    }

    
     
}