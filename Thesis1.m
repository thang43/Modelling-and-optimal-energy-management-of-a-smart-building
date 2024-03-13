yalmip('clear');
%Define parameters
T          = 24;    % Number of time steps     (hours)
r          = 0.012; % self-discharge rate      (%)
eta        = 0.95;  % inverter efficiency      (%)
Ec         = 13.5;  % Energy storage capacity  (kWh)
Pch_c      = 5;     % Charge capacity          (kW)
Pdis_c     = 5;     % Discharge capacity       (kW)
SOCmax     = 100;   % Maximum state of charge  (%)
SOCmin     = 10;    % Minimum state of charge  (%)
SOC_0      = 0.12;  %inital SOC for a daily operation
tau        = 1;     % the operation period     (h)
Pex        = 5;     % power export limit       (kW)
Pim        = 5;     % power import limit       (kW)
Pbl        = 1;     % baseload demand          (kW)
appliance  = 10;    % number of appliances
task       = 3;     % number of tasks
Pdl        = [0.5, 2, 1.5, 1, 0.4, 1.2, 1.2, 0.2, 1.2, 0.8]; % deferrable appliance rated
Ppv_sun    = [ 0; 0   ; 0; 0; 0  ; 0.05;         % PV generation on a sunny day
             0.5; 0.75; 1; 2; 4.5; 5   ;
             4.5; 3.5 ; 3; 1; 0.5; 0.05;
             0  ; 0   ; 0; 0; 0  ; 0  ];

Ppv_cloud  = [ 0; 0   ; 0; 0   ; 0  ; 0.05;      % PV generation on a cloudy day
             0.5; 0.75; 1; 2   ; 3  ; 1.5 ;
             3  ; 2   ; 1; 0.75; 0.5; 0.05;
             0  ; 0   ; 0; 0   ; 0  ; 0  ];

%Decision variables
Pch        = sdpvar(T,1,'full');                % Charging power         (kW)
Pdis       = sdpvar(T,1,'full');                % Discharging power      (kW)
Pdef       = sdpvar(T,1,'full');                % Deficient power        (kW)
Psur       = sdpvar(T,1,'full');                % Surplus power          (kW)
Psh        = sdpvar(T,1,'full');                % Smart home net load demnad (kW)
SOC        = sdpvar(T,1,'full');                % State of charge        (%)
E          = sdpvar(T,1,'full');                % Energy content of BESS (kWh)    
pbuy       = sdpvar(T,1,'full');                % Price for buying       ($/kWh)
psell      = sdpvar(T,1,'full');                % Price for selling      ($/kWh)
Pul        = sdpvar(T,1,'full');                % Uncertain load         (kW)
beta       = binvar(T,1,'full');                % Binary slack variable for linearization
OT         = sdpvar(appliance, task,'full');    % Operating time length required by a task (h)
Pda        = sdpvar(T, appliance, task,'full'); % Deferrable appliance
alpha      = binvar(T, appliance, task,'full'); % Binary slack variable for linearization
sigma      = binvar(T, appliance, task,'full'); % Binary slack variable for linearization


%Constraints
Constraints = [];
for t = 1:T
    psell(t) = 0.05;
    Pul  (t) = 2   ;
    if     t >= 1 && t <= 6 || t >= 22 && t <= 24
        pbuy(t) = 0.156;
    elseif t > 6  && t <= 15 || t > 20 && t < 22
        pbuy(t) = 0.237;
    elseif t > 15 && t <= 20 
        pbuy(t) = 0.549;
    end

   if t == 1
    Constraints = [Constraints, E(t) == SOC_0*Ec*(1 - r) + Pch(t)*eta*tau - Pdis(t)*tau/eta];
   else
    Constraints = [Constraints, E(t) == E(t-1)*(1 - r) + Pch(t)*eta*tau - Pdis(t)*tau/eta];   
   end
   Constraints = [Constraints, SOC(t) == E(t)/Ec];  %SOC Dynamics
   Constraints = [Constraints, SOCmin <= SOC(t) <= SOCmax]; 
   Constraints = [Constraints, 0 <= Pch(t)  <= beta(t)*Pch_c];      %dynamic charging,discharging 
   Constraints = [Constraints, 0 <= Pdis(t) <= (1-beta(t))*Pdis_c];
   
   Constraints = [Constraints, -Pex <= Psh(t) <= Pim];
   Constraints = [Constraints, Psh(t) == Pdef(t) - Psur(t)];
   Constraints = [Constraints, Pdef(t) >= 0];
   Constraints = [Constraints, Psur(t) >= 0];

   %Constraints = [Constraints, Psh(t) == Pbl(t) + Pdl(t) + Pul(t) + Pch(t) - Pdis(t) - Ppv_sun(t)];
end
% Constraints = [Constraints,SOC(24) == SOC_0];

for i = 1:appliance
    for j = 1:task
        for t = 2:T
            Constraints = [Constraints, sigma(t,i,j) <= alpha(t,i,j)   - alpha(t-1,i,j)];
            Constraints = [Constraints, sigma(t,i,j) <= alpha(t-1,i,j) - alpha(t,i,j)];  
        end
        Constraints = [Constraints, sum(sigma(:, i, j)) <= 2];
    end

    for t = 1:T
        Constraints = [Constraints, sum(alpha(t, i, :)) <= 1]; %exclusive task scheduling
    end
end

for i = 1:appliance
    for j = 1:task
        Constraints = [Constraints, sum(alpha(:,i,j)) == OT(i,j)]; %operating time 
        for t = 1:T
            Constraints = [Constraints, Pda(t,i,j) == alpha(t,i,j) * Pdl(i)];
        end
    end
end


%Objective function
objective = sum(pbuy.*Pdef - psell.*Psur)*tau; 

% Solve
options = sdpsettings('solver','gurobi');
% sol = optimize(Constraints, objective, options)

%% results
Res_SOC = value(SOC);

% Extracting the results
if  sol.problem == 0
    disp('Optimal solution found:');
    value(objective)
else
    disp('Problem failed');
end

% Plot the results
t = 1:T; % create a time vector from 1 to T
h = stairs(t, pbuy,'linewidth',2); % create a stairstep plot with blue color

% Label the axes
xlabel('Time (hour)');
ylabel('Cost ($/kWh)');

set(h, 'Color', [0, 0.4470, 0.7410]);
xlim([1 T]);             % Set the x-axis limits from 1 to T 
ylim([0 max(pbuy)+0.1]); % Set the y-axis limits from 0 to just above the max price
grid on                  % Optionally, add a grid for better readability


figure
bar(Res_SOC);
xlabel('Time (hour)')
xticks([1,6,12,18,24])
xticklabels([1,6,12,18,24])
ylabel('SOC (%)')
grid on
 
figure
time_of_day = 1:T; 
plot(time_of_day, Ppv_sun, '-*');
xlabel('Time of Day (hours)');
ylabel('PV Generation (Kw)');
title('PV Generation on a Sunny Day');
legend('PV Generation');
grid on;

figure
time_of_day = 1:T; 
plot(time_of_day, Ppv_cloud, '-*');
xlabel('Time of Day (hours)');
ylabel('PV Generation (Kw)');
title('PV Generation on a Cloudy Day');
legend('PV Generation');
grid on;



                              