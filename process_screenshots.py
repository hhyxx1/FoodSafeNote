
import os
from PIL import Image, ImageEnhance, ImageFilter
import shutil

def resize_image_with_aspect_ratio(img, target_width, target_height, background_color=(0, 0, 0)):
    """调整图片尺寸，保持宽高比，用背景色填充"""
    original_width, original_height = img.size
    original_ratio = original_width / original_height
    target_ratio = target_width / target_height
    
    if original_ratio > target_ratio:
        new_width = target_width
        new_height = int(target_width / original_ratio)
    else:
        new_height = target_height
        new_width = int(target_height * original_ratio)
    
    resized = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    
    new_img = Image.new('RGB', (target_width, target_height), background_color)
    paste_x = (target_width - new_width) // 2
    paste_y = (target_height - new_height) // 2
    new_img.paste(resized, (paste_x, paste_y))
    
    return new_img

def crop_or_pad_to_aspect_ratio(img, aspect_ratio=16/9):
    """裁剪或填充图片到指定宽高比"""
    original_width, original_height = img.size
    original_ratio = original_width / original_height
    
    if original_ratio == aspect_ratio:
        return img
    
    if original_ratio > aspect_ratio:
        new_width = int(original_height * aspect_ratio)
        left = (original_width - new_width) // 2
        right = left + new_width
        return img.crop((left, 0, right, original_height))
    else:
        new_height = int(original_width / aspect_ratio)
        top = (original_height - new_height) // 2
        bottom = top + new_height
        return img.crop((0, top, original_width, bottom))

def create_featured_image(img, width, height, enhance=True):
    """创建推荐图片"""
    img = resize_image_with_aspect_ratio(img, width, height, (30, 30, 30))
    if enhance:
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(1.15)
        enhancer = ImageEnhance.Brightness(img)
        img = enhancer.enhance(1.08)
        enhancer = ImageEnhance.Sharpness(img)
        img = enhancer.enhance(1.1)
    return img

def process_tv_screenshots():
    """处理TV端截图"""
    tv_dir = r'c:\Project\FoodSafeNote3\Screenshots\tv'
    backup_dir = tv_dir + '_backup'
    
    if not os.path.exists(backup_dir):
        shutil.copytree(tv_dir, backup_dir)
    
    files = [f for f in os.listdir(tv_dir) if f.endswith('.png') and 'recommended' not in f]
    
    for file in files:
        img_path = os.path.join(tv_dir, file)
        img = Image.open(img_path).convert('RGB')
        resized = resize_image_with_aspect_ratio(img, 1920, 1080)
        resized.save(img_path, 'PNG', optimize=True)
        print(f'处理TV截图: {file} -> 1920x1080')
    
    if len(files) >= 2:
        img1 = Image.open(os.path.join(tv_dir, files[0])).convert('RGB')
        featured1 = create_featured_image(img1, 396, 223)
        featured1_path = os.path.join(tv_dir, 'recommended_1.png')
        featured1.save(featured1_path, 'PNG', optimize=True)
        print(f'创建推荐图片1: recommended_1.png -> 396x223')
        
        img2 = Image.open(os.path.join(tv_dir, files[1])).convert('RGB')
        featured2 = create_featured_image(img2, 414, 573)
        featured2_path = os.path.join(tv_dir, 'recommended_2.png')
        featured2.save(featured2_path, 'PNG', optimize=True)
        print(f'创建推荐图片2: recommended_2.png -> 414x573')

def process_wearable_screenshots():
    """处理wearable端截图"""
    wearable_dir = r'c:\Project\FoodSafeNote3\Screenshots\wearable'
    backup_dir = wearable_dir + '_backup'
    
    if not os.path.exists(backup_dir):
        shutil.copytree(wearable_dir, backup_dir)
    
    files = [f for f in os.listdir(wearable_dir) if f.endswith('.png')]
    
    for file in files:
        img_path = os.path.join(wearable_dir, file)
        img = Image.open(img_path).convert('RGB')
        resized = resize_image_with_aspect_ratio(img, 840, 840, (20, 20, 20))
        resized.save(img_path, 'PNG', optimize=True)
        print(f'处理wearable截图: {file} -> 840x840')

def process_pc_screenshots():
    """处理PC_2in1端截图"""
    pc_dir = r'c:\Project\FoodSafeNote3\Screenshots\PC_2in1'
    backup_dir = pc_dir + '_backup'
    
    if not os.path.exists(backup_dir):
        shutil.copytree(pc_dir, backup_dir)
    
    files = [f for f in os.listdir(pc_dir) if f.endswith('.png')]
    
    for file in files:
        img_path = os.path.join(pc_dir, file)
        img = Image.open(img_path).convert('RGB')
        width, height = img.size
        
        print(f'PC截图原始尺寸: {file} -> {width}x{height}')
        
        img_cropped = crop_or_pad_to_aspect_ratio(img, 16/9)
        
        cropped_width, cropped_height = img_cropped.size
        
        if cropped_width < 1920 or cropped_height < 1080:
            resized = resize_image_with_aspect_ratio(img_cropped, 1920, 1080)
            resized.save(img_path, 'PNG', optimize=True)
            print(f'处理PC截图: {file} -> 1920x1080 (16:9)')
        else:
            img_cropped.save(img_path, 'PNG', optimize=True)
            print(f'处理PC截图: {file} -> {cropped_width}x{cropped_height} (16:9)')

if __name__ == '__main__':
    print('开始处理截图...\n')
    process_tv_screenshots()
    print()
    process_wearable_screenshots()
    print()
    process_pc_screenshots()
    print('\n截图处理完成！')
