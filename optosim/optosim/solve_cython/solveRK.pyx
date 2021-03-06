import numpy as np
cimport numpy as np
cimport cython
import sys
from libc.math cimport atan2, sin

#cpdef get_z_n(n, z):
#    cdef float z_n
##    e = np.e
#    if n < 0:
#        z_n = 0
#    else:
#        z_n = z[n]
#    return z_n

#cpdef get_I_n_plus_1(In, n, M, Omega0, dt, z, np):
#    In_p1 = In + get_z_n(n, z)*np.exp(-1j*Omega0*n*dt)*dt - get_z_n(n-M, z)*np.exp(-1j*Omega0*(n-M)*dt)*dt
#    return In_p1
#
#cpdef calc_zw0_n(n, In, Omega0, dt, np):
#    zw0_n = np.exp(1j*Omega0*n*dt)*(1/dt)*In
#    return zw0_n
  
@cython.boundscheck(False) # Turns off IndexError type warnings - e.g. a = [1, 2, 3]; a[5]
@cython.wraparound(False) # Turns off Python a[-1] indexing - will segfault.
@cython.overflowcheck(False) # Check that no integer overflows occur with arithmetic operations
@cython.initializedcheck(False) # Checks that memory is initialised when passed in
cpdef solve(np.ndarray[double, ndim=1] q,
            np.ndarray[double, ndim=1] v,
            double dt,
            np.ndarray[double, ndim=1] dwArray,
            double Gamma0,
            double Omega0,
            double b_v,
            double alpha,
            double beta,
            double DoubleFreqAmplitude,
            double DoubleFreqPhaseDelay,
            double SingleFreqAmplitude,
            double SingleFreqPhaseDelay,
            double dTau,
            double feedback_delay_N_periods,
            np.ndarray[double, ndim=1] SqueezingPulseArray,
            int startIndex,
            int NumTimeSteps,
            double mass):
    """
    Solves the SDE specified in sde_solver.py using cythonized python code.
    
    Parameters
    ----------
    q : ndarray
        intialised array of positions (with q[0] = intial position)
    v : ndarray
        intialised array of velocities (with v[0] = intial velocity)
    dt : float
        time interval / step for simulation / solver on which to solve SDE
    dwArray : ndarray
        random values to use for Weiner process
    Gamma0 : float
        Enviromental damping parameter (angular frequency - radians/s) - appears as (-Gamma*v) term in the SDE

    Omega0 : float
        Trapping frequency (angular frequency - radians/s)
    eta : float
        modulation depth (as a fraction)
    b_v : float
        term multiplying the Weiner process in the SDE sqrt(2*Γ0*kB*T0/m)
    alpha : float
        prefactor multiplying the q**3 non-linearity term shows up as ([alpha*q]**3*dt) in the SDE
    beta : float
        prefactor multiplying the q**5 non-linearity term shows up as ([beta*q]**5*dt) in the SDE
    SqueezingPulseArray : ndarray
        Array of values containing modulation depth of squeezing pulses (as a decimal i.e. 1 = 100%)
    startIndex : int
        array index (of q and v) at which to start solving the SDE
    NumTimeSteps : int
        The length of the time array minus 1 (number of time points over which
        to solve the SDE)

    Returns
    -------
    q : ndarray
        array of positions with time found from solving the SDE
    v : ndarray
        array of velocities with time found from solving the SDE
    """
#    print(Gamma0,
#          Omega0,
#          b_v,
#          alpha,
#          beta,
#          DoubleFreqAmplitude,
#          DoubleFreqPhaseDelay,
#          SingleFreqAmplitude,
#          SingleFreqPhaseDelay,
#          dTau,
#          SqueezingPulseArray,
#          startIndex,
#          NumTimeSteps,
#          mass)
    
    cdef int n
    cdef float vK1
    cdef float qK1
    cdef float vh
    cdef float qh
    cdef float vK2
    cdef float qK2
    cdef int M
    cdef float phi_n
    cdef float DoubleFreqFeedback
    cdef float SingleFreqFeedback
    cdef float PowerModulation
    cdef int feedback_index
    
    M = int(dTau/dt)

    freq0 = Omega0/(2*np.pi)
    particle_period = 1/freq0
    feedback_N = int(np.round((feedback_delay_N_periods*particle_period)/dt))
    
    progressbar_width = 50
    relative_progress_for_update = 1/progressbar_width
    timesteps_for_update = np.round(relative_progress_for_update*NumTimeSteps)

    # setup progressbar
    sys.stdout.write("[%s]" % (" " * progressbar_width))
    sys.stdout.flush()
    sys.stdout.write("\b" * (progressbar_width+1)) # return to start of line, after '['

    
    narray = range(startIndex, NumTimeSteps+startIndex)
    S = np.random.choice([-1, 1], NumTimeSteps) # randomly choose -1 or 1 with 50% chance
    
    for n in narray:
        if not n % timesteps_for_update:
            # update the progress bar
            sys.stdout.write("=")
            sys.stdout.flush()

        feedback_index = n-feedback_N
        if feedback_index < 0:
            feedback_index = 0
        phi_n = atan2(v[feedback_index]/Omega0, q[feedback_index])
        
        DoubleFreqFeedback = DoubleFreqAmplitude*sin(2*phi_n + DoubleFreqPhaseDelay)
        SingleFreqFeedback = SingleFreqAmplitude*sin(phi_n + SingleFreqPhaseDelay)

        # stage 1 of 2-stage Runge Kutta
        PowerModulation = (SqueezingPulseArray[n] + DoubleFreqFeedback + SingleFreqFeedback)

        vK1 = ( -Gamma0*v[n] + PowerModulation*(-Omega0**2*q[n] + (alpha*q[n])**3 - (beta*q[n])**5) )*dt + b_v*(dwArray[n] + S[n]*(dt**0.5))
        qK1 = (v[n])*dt 
        
        vh = v[n] + vK1
        qh = q[n] + qK1

        # stage 2 of 2-stage Runge Kutta
        vK2 = ( -Gamma0*vh + PowerModulation*(-Omega0**2*qh + (alpha*qh)**3 - (beta*qh)**5) )*dt + b_v*(dwArray[n] - S[n]*(dt**0.5))
        qK2 = (vh)*dt

        
        # update
        v[n+1] = v[n] + 0.5*(vK1 + vK2)
        q[n+1] = q[n] + 0.5*(qK1 + qK2)

#        In = get_I_n_plus_1(In, n+1, M, Omega0, dt, q, np) # In+1 for next iteration

        
    return q, v


