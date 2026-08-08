function adjusted_img = adjust_brightness_contrast(img, brightness_factor, contrast_factor)
    % Adjust brightness and contrast of a true-color (RGB) image
    % img: input RGB image (uint8)
    % brightness_factor: factor to adjust brightness (e.g., 0.1 for slight increase, -0.1 for decrease)
    % contrast_factor: factor to adjust contrast (e.g., 1.2 for increase, 0.8 for decrease)
    
    % Convert to double for processing
    img_double = double(img) / 255.0;
    
    % Adjust brightness by adding the factor
    img_double = img_double + brightness_factor;
    
    % Adjust contrast by multiplying
    img_double = img_double * contrast_factor;
    
    % Clip values to [0, 1]
    img_double = max(0, min(1, img_double));
    
    % Convert back to uint8
    adjusted_img = uint8(img_double * 255);
end
