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

%Given matrix
A1 = [eta*tau, -tau/eta, -1, (1 - r)];
b1 = 0;

A2 = [-1 Ec];
b2 = 0;

A3_single = [1;-1];
b3_single = [SOCmax;-SOCmin]; 
A3        = kron(eye(T), A3_single);
b3        = repmat(b3_single, T, 1);

A4_single = [1 0 -Pch_c;
             0 1 Pdis_c;
            -1 0  0;
             0 -1 0];
b4_single = [0; Pdis_c;0;0];
A4        = kron(eye(T), A4_single);
b4        = repmat(b4_single, T, 1);

A8        = [1 -1 -1; -1 1 -1];
b8        = [0;0];

A10       = ones(1, T);
b10       = 2;

A11       = ones(1, task);
b11       = 1;

A17_single = [1 -1;-1 1];
b17_single = [Pim;Pex];
A17        = kron(eye(T), A17_single);
b17        = repmat(b17_single, T, 1);

A19_single = [-1 0; 0 -1];
b19_single = [0;0];
A19        = kron(eye(T), A19_single);
b19        = repmat(b19_single, T, 1);

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
end
if t == 1
    Constraints = [Constraints, A1 * [Pch(t); Pdis(t); E(t); SOC_0*Ec] == b1];
   
else
    for t = 2:T 
    Constraints = [Constraints, A1 * [Pch(t); Pdis(t); E(t); E(t-1)] == b1];
    end
end

for i = 1:appliance
    for j = 1:task
        for t = 2:T
            %Constraints = [Constraints, sigma(t,i,j) <= alpha(t,i,j) - alpha(t-1,i,j)];
            %Constraints = [Constraints, sigma(t,i,j) <= alpha(t-1,i,j) - alpha(t,i,j)];
            Constraints = [Constraints, A8 * [alpha(t,i,j); alpha(t-1,i,j); sigma(t,i,j)] <= b8];
        end
        Constraints = [Constraints, A10 * squeeze(sigma(:, i, j)) <= b10];
    end

    for t = 1:T
        Constraints = [Constraints, A2 * [E(t); SOC(t)] == b2];
        Constraints = [Constraints, A11 * squeeze(alpha(t, i, :)) <= b11]; %exclusive task scheduling
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

Constraints = [Constraints, A3 *  SOC <= b3]; %SOC Dynamics
Constraints = [Constraints, A4 * [Pch; Pdis; beta] <= b4]; %dynamic charging,discharging 
Constraints = [Constraints, A17* [Pdef;Psur] <= b17];
Constraints = [Constraints, A19* [Pdef;Psur] <= b19];
Constraints = [Constraints, Psh == Pdef - Psur];

Psh = Pbl + Pdl + Pul + Pch - Pdis - Ppv_sun;
%Objective function
objective = sum(pbuy.*Pdef - psell.*Psur)*tau; 

% Solve
options = sdpsettings('solver','gurobi');
sol = optimize(Constraints, objective, options);

% Extracting the results
if  sol.problem == 0
    disp('Optimal solution found:');
    value(objective)
else
    disp('Problem failed');
end
% Now, plot the results
t = 1:T; % create a time vector from 1 to T
h = stairs(t, pbuy,'linewidth',2); % create a stairstep plot with blue color

% Label the axes
xlabel('Time (hours)');
ylabel('Cost ($/kWh)');

set(h, 'Color', [0, 0.4470, 0.7410]);
xlim([1 T]); % Set the x-axis limits from 1 to T (24 in this case)
ylim([0 max(pbuy)+0.1]); % Set the y-axis limits from 0 to just above the max price
% Optionally, add a grid for better readability
grid on