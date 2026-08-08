function navAngle = mathToNavAngle(mathAngle)
    % 将数学角度转换为导航角度
    % mathAngle: 以正东方向为0度，逆时针增加的
    % navAngle: 以正北方向为0度，顺时针增加的
    navAngle = mod(90 - mathAngle, 360);
end
